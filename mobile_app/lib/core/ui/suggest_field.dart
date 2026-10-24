import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import 'job_catalog.dart';
import 'widgets.dart';

/// A text field with a big drop-down list that filters while the person types. Anything can be typed: the list only
/// suggests, it never blocks saving. [options] is asked again on every keystroke, so it can depend on other fields
/// (job titles follow the chosen department).
class SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final List<Suggestion> Function() options;
  final String? Function(String?)? validator;
  final String? hint;
  /// Shown under the field when what is typed matches nothing in the list.
  final String? noMatchHint;
  const SuggestField({super.key, required this.controller, required this.label, required this.options, this.icon, this.validator, this.hint, this.noMatchHint});

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();
  bool _noMatch = false;

  List<Suggestion> _filter(String text) {
    final all = widget.options();
    final q = normJob(text);
    if (q.isEmpty) return all;
    return all.where((o) => normJob(o.label).contains(q) || (o.alt.isNotEmpty && normJob(o.alt).contains(q))).toList();
  }

  void _onChanged(String text) {
    final none = text.trim().isNotEmpty && _filter(text).isEmpty;
    if (none != _noMatch) setState(() => _noMatch = none);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return RawAutocomplete<Suggestion>(
        textEditingController: widget.controller,
        focusNode: _focus,
        displayStringForOption: (o) => o.label,
        optionsBuilder: (v) => _filter(v.text),
        fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: widget.validator,
          onChanged: _onChanged,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            helperText: _noMatch ? widget.noMatchHint : null,
            helperMaxLines: 2,
            prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 22),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down_rounded),
              onPressed: () {
                if (focusNode.hasFocus) {
                  focusNode.unfocus();
                } else {
                  focusNode.requestFocus();
                }
              },
            ),
          ),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 280, maxWidth: box.maxWidth),
              child: SizedBox(
                width: box.maxWidth,
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final o = options.elementAt(i);
                    return InkWell(
                      onTap: () {
                        onSelected(o);
                        _onChanged(o.label);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        child: Row(children: [
                          Expanded(child: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w600))),
                          if (o.alt.isNotEmpty) Text(o.alt, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Department name field: suggests every department a company can have, accepts any other name.
Widget departmentSuggestField(BuildContext context, TextEditingController c, {required String label, IconData icon = Icons.account_tree_outlined, String? Function(String?)? validator}) {
  return SuggestField(
    controller: c,
    label: label,
    icon: icon,
    validator: validator,
    hint: context.t('job.pick_hint'),
    noMatchHint: context.t('job.new_hint'),
    options: () => departmentOptions(context.isAr ? 'ar' : 'en'),
  );
}

/// Job title field: suggests the titles that fit the department chosen right now (plus titles already used there).
Widget titleSuggestField(BuildContext context, TextEditingController c, {required String label, required String Function() department, required List<String> Function() existing, IconData icon = Icons.work_outline_rounded}) {
  return SuggestField(
    controller: c,
    label: label,
    icon: icon,
    hint: context.t('job.pick_hint'),
    noMatchHint: context.t('job.new_title_hint'),
    options: () => titleOptions(department(), context.isAr ? 'ar' : 'en', existing()),
  );
}

/// True when it is fine to save: the title is in the list, or the person agreed to save it as a new title.
Future<bool> confirmNewTitle(BuildContext context, String title, String department, [List<String> existing = const []]) async {
  final t = title.trim();
  if (t.isEmpty || isKnownTitle(t, department, context.isAr ? 'ar' : 'en', existing)) return true;
  return confirmDialog(context, title: context.t('job.confirm_title'), message: context.t('job.confirm_msg', {'title': t}), confirmLabel: context.t('job.save_new'));
}
