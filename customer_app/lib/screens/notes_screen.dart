import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/customer_models.dart';
import '../theme.dart';

/// Read-only timeline of admin notes attached to the customer's record.
/// Source data is the `customer.action_notes` JSON blob the staff side
/// edits — we just render whatever entries the server hands back.
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key, required this.customer});
  final Customer customer;

  List<ActionNote> _parseNotes() {
    final raw = customer.actionNotesRaw.trim();
    if (raw.isEmpty || raw == 'null') return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => ActionNote.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final notes = _parseNotes();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        backgroundColor: Brand.canvas,
        scrolledUnderElevation: 0,
        elevation: 0,
        shape: const Border(
          bottom: BorderSide(color: Brand.stroke),
        ),
      ),
      body: notes.isEmpty
          ? const _EmptyNotes()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NoteCard(note: notes[i]),
            ),
    );
  }
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Brand.signalGlow(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.note_alt_outlined,
                  color: Brand.signal, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'No notes yet',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Brand.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When the support team adds an update to your record, it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Brand.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final ActionNote note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: Brand.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.support_agent,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.author,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (note.createdAt.isNotEmpty)
                      Text(
                        note.createdAt,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Brand.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            note.note,
            style: const TextStyle(
              fontSize: 14,
              color: Brand.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
