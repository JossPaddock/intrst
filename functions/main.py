from typing import Any

import firebase_admin
from firebase_admin import auth, firestore, messaging
from firebase_functions import firestore_fn, https_fn

firebase_admin.initialize_app()

# ---------------------------------------------------------------------------
# Admin allowlist
# ---------------------------------------------------------------------------
# Emails permitted to call admin-only callable functions (see
# `admin_delete_user`). A caller is also authorized if their auth token carries
# a custom claim `admin == true`. This server-side check is the real security
# boundary: the Flutter admin dashboard is gated to web + debug builds, but the
# callable function itself is reachable by anyone on the internet, so it must
# never trust the client gate alone.
ADMIN_EMAILS = {
    "joss.self@gmail.com",
    "josspaddock@hotmail.com",
}


def _is_admin_caller(auth_data) -> bool:
    """True when the callable request comes from an authorized admin."""
    if auth_data is None:
        return False
    token = getattr(auth_data, "token", None) or {}
    if token.get("admin") is True:
        return True
    email = token.get("email")
    return bool(email) and email.lower() in {e.lower() for e in ADMIN_EMAILS}


def _cleanup_stale_tokens(users_ref, uid, all_tokens, response):
    """Remove FCM tokens that FCM has reported as invalid."""
    tokens_to_remove = [
        all_tokens[i]
        for i, result in enumerate(response.responses)
        if not result.success
        and result.exception
        and hasattr(result.exception, 'code')
        and result.exception.code in (
            'registration-token-not-registered',
            'invalid-registration-token',
        )
    ]
    if not tokens_to_remove:
        return
    try:
        user_docs = list(
            users_ref.where(
                filter=firestore.FieldFilter("user_uid", "==", uid)
            ).stream()
        )
        if user_docs:
            updated = [t for t in all_tokens if t not in tokens_to_remove]
            user_docs[0].reference.update({"fcm_tokens": updated})
            print(f"Removed {len(tokens_to_remove)} stale token(s) for {uid}.")
    except Exception as e:
        print(f"Failed to clean up tokens for {uid}: {e}")


def _send_to_user(users_ref, uid, actor_uid, title, body, data_payload):
    """
    Look up a user by uid, calculate their badge count, and send
    a multicast notification to all their FCM tokens.
    Returns True if the send was attempted, False if skipped.
    """
    user_docs = list(
        users_ref.where(
            filter=firestore.FieldFilter("user_uid", "==", uid)
        ).stream()
    )
    if not user_docs:
        print(f"No user found for {uid}")
        return False

    user_doc = user_docs[0].to_dict()

    notifications = user_doc.get("unread_notifications_count", {})
    if not isinstance(notifications, dict):
        notifications = {}
    badge_count = sum(
        int(v) for v in notifications.values() if isinstance(v, (int, float))
    )

    fcm_tokens = user_doc.get("fcm_tokens", [])
    if not fcm_tokens:
        print(f"No FCM tokens for {uid}")
        return False

    multicast_message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        tokens=fcm_tokens,
        apns=messaging.APNSConfig(
            headers={
                # High priority so iOS wakes the app even in background
                "apns-priority": "10",
            },
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    badge=badge_count,
                    # content_available ensures delivery when app is backgrounded
                    content_available=True,
                )
            ),
        ),
        data={k: str(v) for k, v in data_payload.items() if v is not None},
    )

    response = messaging.send_each_for_multicast(multicast_message)
    print(f"Sent to {uid}: {response.success_count}/{len(fcm_tokens)} success.")
    _cleanup_stale_tokens(users_ref, uid, fcm_tokens, response)
    return True


@firestore_fn.on_document_created(document="activity_feed/{activityId}")
def on_activity_created(
    event: firestore_fn.Event[firestore_fn.DocumentSnapshot]
):
    data = event.data.to_dict()
    if not data:
        return

    activity_type = data.get("type", "")
    actor_name = data.get("actor_name", "Someone")
    actor_uid = data.get("actor_uid")
    target_uids = data.get("target_uids", [])
    interest_id = data.get("interest_id")
    interest_name = data.get("interest_name")

    # Only notify for these two activity types
    NOTIFIABLE_TYPES = {"interest_created", "interest_updated", "interest_shared"}
    if activity_type not in NOTIFIABLE_TYPES:
        print(f"Activity type '{activity_type}' is not notifiable, skipping.")
        return

    if not target_uids:
        return

    interest_label = f' "{interest_name}"' if interest_name else " an interest"
    body_map = {
        "interest_created": f"{actor_name} created{interest_label}.",
        "interest_updated": f"{actor_name} updated{interest_label}.",
        "interest_shared": f"{actor_name} just shared an interest with you called{interest_label}.",
    }
    body = body_map.get(activity_type, f"{actor_name} has new activity.")

    db = firestore.client()
    users_ref = db.collection("users")

    for target_uid in target_uids:
        if target_uid == actor_uid:
            continue
        try:
            _send_to_user(
                users_ref,
                uid=target_uid,
                actor_uid=actor_uid,
                title=actor_name,
                body=body,
                data_payload={
                    "activity_type": activity_type,
                    "actor_uid": actor_uid or "",
                    "interest_id": interest_id or "",
                },
            )
        except Exception as e:
            print(f"Error processing target {target_uid}: {e}")


@firestore_fn.on_document_updated(document="messages/{messageId}")
def on_message_updated(
    event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]
):
    if not event.data.after:
        print("No after snapshot, ignoring.")
        return

    data_after = event.data.after.to_dict()
    convo_after = data_after.get("conversation", {})

    if not isinstance(convo_after, dict) or not convo_after:
        print("No conversation map found, returning.")
        return

    # Find the message with the latest timestamp.
    # We do NOT diff before/after because Firestore sends the full nested map
    # in both snapshots when a sub-key is added — the key diff is always empty.
    # Instead we pick the latest-by-timestamp message and use the transaction
    # below purely as the duplicate/idempotency guard.
    latest_key = None
    latest_message = None
    latest_timestamp = None

    for key, msg in convo_after.items():
        if not isinstance(msg, dict):
            continue
        ts = msg.get("timestamp")
        if ts and (latest_timestamp is None or ts > latest_timestamp):
            latest_timestamp = ts
            latest_message = msg
            latest_key = key

    if not latest_key or not latest_message:
        print("Could not find a latest message, returning.")
        return

    print(f"Latest message key: {latest_key}, timestamp: {latest_timestamp}")

    # Idempotency: claim the key atomically so retries and rapid successive
    # writes can't send duplicate notifications.
    db = firestore.client()
    message_doc_ref = db.collection("messages").document(event.params["messageId"])

    @firestore.transactional
    def claim_key(transaction, doc_ref):
        snapshot = doc_ref.get(transaction=transaction)
        snapshot_data = snapshot.to_dict() or {}
        already_notified = set(snapshot_data.get("notified_message_keys") or [])
        if latest_key in already_notified:
            return False
        transaction.update(doc_ref, {
            "notified_message_keys": list(already_notified | {latest_key})
        })
        return True

    transaction = db.transaction()
    try:
        should_notify = claim_key(transaction, message_doc_ref)
    except Exception as e:
        print(f"Transaction failed: {e}")
        return

    if not should_notify:
        print(f"Key {latest_key} already notified, skipping.")
        return

    sender_uid = latest_message.get("user_uid")
    message_content = latest_message.get("message_content", "You have a new message.")

    if not sender_uid:
        print("No sender_uid on latest message, returning.")
        return

    all_participant_uids = data_after.get("user_uids", [])
    receiver_uids = [uid for uid in all_participant_uids if uid != sender_uid]

    print(f"sender: {sender_uid}, receivers: {receiver_uids}")

    if not receiver_uids:
        print("No receivers after filtering out sender.")
        return

    users_ref = db.collection("users")

    first_name, last_name = "New", "Message"
    try:
        for doc in users_ref.where(
            filter=firestore.FieldFilter("user_uid", "==", sender_uid)
        ).stream():
            d = doc.to_dict()
            first_name = d.get("first_name", "New")
            last_name = d.get("last_name", "Message")
    except Exception as e:
        print(f"Error fetching sender name: {e}")

    for receiver_uid in receiver_uids:
        try:
            _send_to_user(
                users_ref,
                uid=receiver_uid,
                actor_uid=sender_uid,
                title=f"{first_name} {last_name}",
                body=message_content,
                data_payload={
                    # ↓ CHANGED: sender_uid now included so the Flutter app
                    #   can deep-link directly to this conversation on tap.
                    "sender_uid": sender_uid or "",
                },
            )
        except Exception as e:
            print(f"Error processing receiver {receiver_uid}: {e}")


# ---------------------------------------------------------------------------
# Admin: fully delete a user (Firebase Auth account + all Firestore data)
# ---------------------------------------------------------------------------
def _commit_in_batches(db, operations):
    """Apply a list of (kind, ref, payload) ops in <=400-write batches.

    kind is 'delete' or 'update'; payload is ignored for deletes.
    """
    batch = db.batch()
    count = 0
    committed = 0
    for kind, ref, payload in operations:
        if kind == "delete":
            batch.delete(ref)
        else:
            batch.update(ref, payload)
        count += 1
        if count >= 400:
            batch.commit()
            committed += count
            batch = db.batch()
            count = 0
    if count:
        batch.commit()
        committed += count
    return committed


def _delete_subcollection(doc_ref, subcollection):
    """Delete every document in a subcollection (subcollections are not removed
    automatically when their parent document is deleted)."""
    deleted = 0
    for sub_doc in doc_ref.collection(subcollection).stream():
        sub_doc.reference.delete()
        deleted += 1
    return deleted


def _purge_user_firestore_data(db, target_uid):
    """Remove the user's own document(s) plus every cross-reference to them.

    Returns a summary dict describing what was cleaned up.
    """
    users_ref = db.collection("users")
    summary = {
        "user_docs_deleted": 0,
        "friendship_docs_deleted": 0,
        "following_or_friend_refs_removed": 0,
        "activity_feed_docs_deleted": 0,
        "activity_feed_targets_scrubbed": 0,
        "message_threads_deleted": 0,
    }

    # 1. The user's own document(s) and their friendships subcollection.
    own_docs = list(
        users_ref.where(
            filter=firestore.FieldFilter("user_uid", "==", target_uid)
        ).stream()
    )
    for doc in own_docs:
        summary["friendship_docs_deleted"] += _delete_subcollection(
            doc.reference, "friendships"
        )
        doc.reference.delete()
        summary["user_docs_deleted"] += 1

    # 2. Other users referencing the target in following_uids / friends_uids,
    #    plus a friendships/{target_uid} doc pointing back at them.
    ops = []
    referencing_ids = set()
    for field in ("following_uids", "friends_uids"):
        for doc in users_ref.where(
            filter=firestore.FieldFilter(field, "array_contains", target_uid)
        ).stream():
            ops.append((
                "update",
                doc.reference,
                {field: firestore.ArrayRemove([target_uid])},
            ))
            referencing_ids.add(doc.id)
    summary["following_or_friend_refs_removed"] += len(ops)
    if ops:
        _commit_in_batches(db, ops)

    # Delete the reciprocal friendship doc other users hold for the target.
    for doc in users_ref.stream():
        friendship_ref = doc.reference.collection("friendships").document(
            target_uid
        )
        if friendship_ref.get().exists:
            friendship_ref.delete()
            summary["friendship_docs_deleted"] += 1

    # 3. Activity feed: delete items authored by the target, and scrub the
    #    target out of other people's target_uids arrays.
    activity_ref = db.collection("activity_feed")
    del_ops = [
        ("delete", doc.reference, None)
        for doc in activity_ref.where(
            filter=firestore.FieldFilter("actor_uid", "==", target_uid)
        ).stream()
    ]
    summary["activity_feed_docs_deleted"] = len(del_ops)
    if del_ops:
        _commit_in_batches(db, del_ops)

    scrub_ops = [
        ("update", doc.reference, {
            "target_uids": firestore.ArrayRemove([target_uid])
        })
        for doc in activity_ref.where(
            filter=firestore.FieldFilter(
                "target_uids", "array_contains", target_uid
            )
        ).stream()
    ]
    summary["activity_feed_targets_scrubbed"] = len(scrub_ops)
    if scrub_ops:
        _commit_in_batches(db, scrub_ops)

    # 4. Message threads the target participated in.
    messages_ref = db.collection("messages")
    msg_ops = [
        ("delete", doc.reference, None)
        for doc in messages_ref.where(
            filter=firestore.FieldFilter(
                "user_uids", "array_contains", target_uid
            )
        ).stream()
    ]
    summary["message_threads_deleted"] = len(msg_ops)
    if msg_ops:
        _commit_in_batches(db, msg_ops)

    return summary


@https_fn.on_call()
def admin_delete_user(req: https_fn.CallableRequest) -> Any:
    """Callable: permanently delete a user's Firebase Auth account and every
    trace of their data in Firestore. Admin-only.

    Request data: { "target_uid": "<user_uid>" }
    """
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="You must be signed in to perform this action.",
        )
    if not _is_admin_caller(req.auth):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="You are not authorized to delete users.",
        )

    data = req.data if isinstance(req.data, dict) else {}
    target_uid = (data.get("target_uid") or "").strip()
    if not target_uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="A non-empty 'target_uid' is required.",
        )
    if target_uid == req.auth.uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Admins cannot delete their own account here.",
        )

    db = firestore.client()

    # Clean Firestore first so that, even if auth deletion fails, we do not
    # leave the user's data behind.
    try:
        summary = _purge_user_firestore_data(db, target_uid)
    except Exception as e:
        print(f"admin_delete_user: Firestore purge failed for {target_uid}: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Failed to delete user data: {e}",
        )

    # Delete the Firebase Auth account. A missing auth user is not fatal — the
    # Firestore data is already gone, so we report it and succeed.
    auth_deleted = False
    try:
        auth.delete_user(target_uid)
        auth_deleted = True
    except auth.UserNotFoundError:
        print(f"admin_delete_user: no auth account for {target_uid}.")
    except Exception as e:
        print(f"admin_delete_user: auth deletion failed for {target_uid}: {e}")
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=(
                "User data was deleted, but removing the auth account failed: "
                f"{e}"
            ),
        )

    print(
        f"admin_delete_user: {req.auth.uid} deleted {target_uid} "
        f"(auth_deleted={auth_deleted}, summary={summary})"
    )
    return {
        "success": True,
        "target_uid": target_uid,
        "auth_deleted": auth_deleted,
        "summary": summary,
    }


@https_fn.on_call()
def admin_get_user_emails(req: https_fn.CallableRequest) -> Any:
    """Callable: return { uid: email } for the requested user uids. Admin-only.

    Emails are stored in Firebase Auth, not Firestore, so the admin dashboard
    looks them up here (via the Admin SDK) to display alongside each user.

    Request data: { "uids": ["<uid>", ...] }
    """
    if req.auth is None:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="You must be signed in to perform this action.",
        )
    if not _is_admin_caller(req.auth):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="You are not authorized to view user emails.",
        )

    data = req.data if isinstance(req.data, dict) else {}
    raw_uids = data.get("uids") or []

    # Normalize + de-duplicate while preserving order.
    seen = set()
    unique_uids = []
    for value in raw_uids:
        uid = str(value).strip()
        if uid and uid not in seen:
            seen.add(uid)
            unique_uids.append(uid)

    emails = {}
    # auth.get_users accepts at most 100 identifiers per call.
    for start in range(0, len(unique_uids), 100):
        chunk = unique_uids[start:start + 100]
        try:
            result = auth.get_users(
                [auth.UidIdentifier(uid) for uid in chunk]
            )
            for user in result.users:
                emails[user.uid] = user.email or ""
        except Exception as e:
            print(f"admin_get_user_emails: lookup failed for a chunk: {e}")

    return {"emails": emails}