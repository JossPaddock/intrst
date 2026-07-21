part of '../CardList.dart';

// Modal dialogs used while creating/editing/deleting an interest.
mixin _CardListDialogsMixin on _CardListStateBase {
  @override
  Future<void> _showBlankInterestDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Missing content'),
        content: const Text('This interest will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> _openFullscreenRichTextEditor(
    RichTextEditorController richTextController,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Enter/edit description'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
          body: Container(
            padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
            child: RichTextEditorWidget(
              mode: RichTextEditorMode.edit,
              controller: richTextController,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: 'enter your interest here',
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Future<void> _showInvalidLinkDialog() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invalid link'),
        content: const Text(
          'The link you entered does not appear to be reachable. '
          'Please try fix it before saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> _showPostInterestToFeedDialog(Interest interest) async {
    if (widget.uid.trim().isEmpty) return;

    final TextEditingController postMessageController = TextEditingController();
    bool isPosting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Post "${interest.name}" to your feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: postMessageController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Say something about this interest...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isPosting
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isPosting
                      ? null
                      : () async {
                          final message = postMessageController.text.trim();
                          if (message.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please add a message before posting.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isPosting = true;
                          });

                          try {
                            await fu.createInterestPostedActivity(
                              actorUid: widget.uid,
                              interest: interest,
                              message: message,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('Posted to feed.')),
                            );
                          } catch (e) {
                            setDialogState(() {
                              isPosting = false;
                            });
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Could not post: $e')),
                            );
                          }
                        },
                  child: isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Post to my Feed'),
                ),
              ],
            );
          },
        );
      },
    );

    postMessageController.dispose();
  }

  // Shows a modal prompting the user to enter a name before the interest is
  // created. Returns the trimmed name string, or null if the user cancelled.
  @override
  Future<String?> _showCreateInterestDialog({String? initialName}) async {
    final TextEditingController nameController = TextEditingController(
      text: initialName,
    );
    String? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Name your interest'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Astrophysics, Jazz guitar…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    result = value.trim();
                    Navigator.of(dialogContext).pop();
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    result = null;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: nameController.text.trim().isEmpty
                      ? null
                      : () {
                          result = nameController.text.trim();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Create Interest'),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameController.dispose();
    });
    return result;
  }

  @override
  Future<bool?> _showSaveDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must choose
      builder: (context) {
        return AlertDialog(
          title: const Text("You may have unsaved changes"),
          content: const Text("Do you want to save your work?"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // discard
              },
              child: const Text("Discard"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // save
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }
}
