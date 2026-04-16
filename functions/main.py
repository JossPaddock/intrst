import firebase_admin
from firebase_admin import firestore, messaging
from firebase_functions import firestore_fn

firebase_admin.initialize_app()


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
    NOTIFIABLE_TYPES = {"interest_created", "interest_updated"}
    if activity_type not in NOTIFIABLE_TYPES:
        print(f"Activity type '{activity_type}' is not notifiable, skipping.")
        return

    if not target_uids:
        return

    interest_label = f' "{interest_name}"' if interest_name else " an interest"
    body_map = {
        "interest_created": f"{actor_name} created{interest_label}.",
        "interest_updated": f"{actor_name} updated{interest_label}.",
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
                data_payload={},
            )
        except Exception as e:
            print(f"Error processing receiver {receiver_uid}: {e}")