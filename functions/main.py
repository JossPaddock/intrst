import firebase_admin
from firebase_admin import firestore, messaging
from firebase_functions import firestore_fn
# We already import firestore_fn above. The alias was wrong.

# Initialize the Firebase Admin SDK.
firebase_admin.initialize_app()

@firestore_fn.on_document_updated(document="messages/{messageId}")
def on_message_updated(
    # This line is changed to use the correct 'firestore_fn' import
    event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]
):
    """
    Triggers when a 'messages' document is updated (i.e., a new message is added).
    It identifies the new message, finds the sender, determines all other
    participants as receivers, and sends them a notification.
    """

    # Get the data before and after the change
    if not event.data.after:
        print("Document deleted, ignoring.")
        return

    data_before = event.data.before.to_dict() if event.data.before else {}
    data_after = event.data.after.to_dict()

    # Find what's new in the 'conversation' map
    convo_before_keys = data_before.get("conversation", {}).keys()
    convo_after = data_after.get("conversation", {})
    convo_after_keys = convo_after.keys()

    new_message_keys = convo_after_keys - convo_before_keys

    if not new_message_keys:
        print("No new messages found in conversation update, ignoring.")
        return

    # Find the single latest new message (in case of a multi-message batch update)
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

    # Get all participants in the conversation
    all_participant_uids = data_after.get("user_uids", [])
    if not all_participant_uids:
        print(f"Message doc {event.params['messageId']} has no 'user_uids' array. Skipping.")
        return

    # Receivers are all participants *except* the sender
    receiver_uids = [uid for uid in all_participant_uids if uid != sender_uid]

    if not receiver_uids:
        print(f"No receivers for this message (sender: {sender_uid}).")
        return

    print(f"New message from {sender_uid}. Sending notifications to {len(receiver_uids)} receivers.")

    # --- Get Receiver FCM Tokens ---

    db = firestore.client()
    users_ref = db.collection("users")
    all_tokens = []

    # Firestore 'in' queries are limited to 30 items.
    # We must batch the receiver UIDs into chunks of 30.
    for i in range(0, len(receiver_uids), 30):
        batch_uids = receiver_uids[i:i+30]

        try:
            # Query for user documents where 'user_uid' is in our batch
            query = users_ref.where(filter=firestore.FieldFilter("user_uid", "in", batch_uids))
            docs = query.stream()

            for doc in docs:
                user_data = doc.to_dict()
                fcm_tokens = user_data.get('fcm_tokens', [])
                if fcm_tokens and isinstance(fcm_tokens, list):
                    # Add only valid, non-empty tokens
                    all_tokens.extend(token for token in fcm_tokens if token)
        except Exception as e:
            print(f"Error querying user batch {i//30}: {e}")

    # Remove duplicate tokens
    unique_tokens = list(set(all_tokens))

    if not unique_tokens:
        print("No valid FCM tokens found for any receivers.")
        return

    first_name = "New"
    last_name = "Message"

    try:
            name_query = users_ref.where(filter=firestore.FieldFilter("user_uid", "in", [sender_uid]))
            name_docs = name_query.stream()

            for name_doc in name_docs:
                user_name_data = name_doc.to_dict()
                first_name = user_name_data.get('first_name', "New")
                last_name = user_name_data.get('last_name', "Message")

    except Exception as e:
        print(f"Error fetching sender name")

    # --- Send Notifications ---

    # Prepare the MulticastMessage
    multicast_message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title=f"{first_name} {last_name}",
            body=message_content
        ),
        # You could also add a 'data' payload here if the app needs it
        # data={
        #     "messageId": event.params['messageId'],
        #     "senderUid": sender_uid
        # }
        tokens=unique_tokens
    )

    # Send the message
    try:
        response = messaging.send_each_for_multicast(multicast_message)

        print(f"Notifications sent successfully: {response.success_count} / {len(unique_tokens)}")
        if response.failure_count > 0:
            print(f"Failed to send to {response.failure_count} devices. Logging errors...")
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    # Log the failed token and the error
                    print(f"Failed to send to token {unique_tokens[idx]}: {resp.exception}")
                    # TODO: Consider adding logic here to remove invalid/stale tokens
                    # from your 'users' collection.

    except Exception as e:
        print(f"Error sending multicast message: {e}")