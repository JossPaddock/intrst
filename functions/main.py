import firebase_admin
from firebase_admin import firestore, messaging
from firebase_functions import firestore_fn

# Initialize the Firebase Admin SDK.
firebase_admin.initialize_app()

@firestore_fn.on_document_updated(document="messages/{messageId}")
def on_message_updated(
    event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]
):
    """
    Triggers when a 'messages' document is updated.
    Sends a notification with an iOS badge number to all participants except the sender.
    """

    # --- Get the data before and after the change ---
    if not event.data.after:
        print("Document deleted, ignoring.")
        return

    data_before = event.data.before.to_dict() if event.data.before else {}
    data_after = event.data.after.to_dict()

    # Find new messages
    convo_before_keys = data_before.get("conversation", {}).keys()
    convo_after = data_after.get("conversation", {})
    new_message_keys = convo_after.keys() - convo_before_keys

    if not new_message_keys:
        print("No new messages found in conversation update, ignoring.")
        return

    # Find the latest new message
    latest_new_message = None
    latest_timestamp = None
    for key in new_message_keys:
        message = convo_after.get(key)
        if not message:
            continue
        timestamp = message.get("timestamp")
        if not latest_timestamp or (timestamp and timestamp > latest_timestamp):
            latest_timestamp = timestamp
            latest_new_message = message

    if not latest_new_message:
        print("Could not determine the new message. Skipping.")
        return

    # --- Identify Sender and Receivers ---
    sender_uid = latest_new_message.get("user_uid")
    message_content = latest_new_message.get("message_content", "You have a new message!")

    if not sender_uid:
        print("New message has no 'user_uid'. Skipping.")
        return

    all_participant_uids = data_after.get("user_uids", [])
    if not all_participant_uids:
        print(f"Message doc {event.params['messageId']} has no 'user_uids' array. Skipping.")
        return

    receiver_uids = [uid for uid in all_participant_uids if uid != sender_uid]
    if not receiver_uids:
        print(f"No receivers for this message (sender: {sender_uid}).")
        return

    print(f"New message from {sender_uid}. Sending notifications to {len(receiver_uids)} receivers.")

    # --- Get Firestore references ---
    db = firestore.client()
    users_ref = db.collection("users")

    # --- Prepare sender info ---
    first_name, last_name = "New", "Message"
    try:
        name_query = users_ref.where(filter=firestore.FieldFilter("user_uid", "in", [sender_uid]))
        name_docs = name_query.stream()
        for name_doc in name_docs:
            user_name_data = name_doc.to_dict()
            first_name = user_name_data.get('first_name', "New")
            last_name = user_name_data.get('last_name', "Message")
    except Exception as e:
        print(f"Error fetching sender name: {e}")

    # --- Loop over receivers ---
    for receiver_uid in receiver_uids:
        try:
            user_query = users_ref.where(filter=firestore.FieldFilter("user_uid", "==", receiver_uid))
            user_docs = list(user_query.stream())

            if not user_docs:
                print(f"No user found for receiver {receiver_uid}")
                continue

            user_doc = user_docs[0].to_dict()

            # --- Calculate badge count (mirrors Dart logic) ---
            notifications = user_doc.get("unread_notifications_count", {})
            if not isinstance(notifications, dict):
                notifications = {}

            badge_count = sum(
                int(v) for v in notifications.values() if isinstance(v, (int, float))
            )

            # --- Get FCM tokens ---
            fcm_tokens = user_doc.get("fcm_tokens", [])
            if not fcm_tokens:
                print(f"No FCM tokens for receiver {receiver_uid}")
                continue

            # --- Send the notification ---
            multicast_message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=f"{first_name} {last_name}",
                    body=message_content
                ),
                tokens=fcm_tokens,
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(badge=badge_count)
                    )
                )
            )

            response = messaging.send_each_for_multicast(multicast_message)
            print(f"Sent to {receiver_uid}: {response.success_count}/{len(fcm_tokens)} success.")

        except Exception as e:
            print(f"Error processing receiver {receiver_uid}: {e}")