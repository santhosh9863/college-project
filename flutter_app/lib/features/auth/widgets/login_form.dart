import 'package:flutter/material.dart';

/// Shared client-side validation rules for the login form.
///
/// These mirror the server-side limits (username <= 64 chars, password <= 128
/// chars) and reject obviously malformed input before any network call.
String? validateUsername(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Username is required';
  if (trimmed.length > 64) return 'Username is too long';
  if (trimmed.contains(RegExp(r'\s'))) return 'Username cannot contain spaces';
  return null;
}

String? validatePassword(String? value) {
  final entered = value ?? '';
  if (entered.isEmpty) return 'Password is required';
  if (entered.length > 128) return 'Password is too long';
  return null;
}

class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.onSubmit,
    required this.busy,
  });

  /// Invoked with the validated, trimmed credentials. The password is used
  /// in-memory only and never logged or stored by the app.
  final Future<void> Function(String username, String password) onSubmit;
  final bool busy;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.onSubmit(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameController,
              enabled: !widget.busy,
              autofillHints: const [AutofillHints.username],
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'Register number or student ID',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: validateUsername,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              enabled: !widget.busy,
              autofillHints: const [AutofillHints.password],
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => widget.busy ? null : _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: validatePassword,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: widget.busy ? null : _submit,
              child: widget.busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
