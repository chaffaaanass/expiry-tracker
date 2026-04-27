import 'package:flutter/material.dart';
import '../services/odoo_service.dart';
import '../services/background_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _urlCtrl  = TextEditingController(text: 'http://');
  final _dbCtrl   = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool    _loading     = false;
  bool    _obscurePass = true;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      OdooService.instance.configure(
        baseUrl:  _urlCtrl.text.trim(),
        database: _dbCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );

      await OdooService.instance.authenticate();
      await OdooService.instance.saveToPrefs();

      await BackgroundService.startPolling();
      await BackgroundService.scheduleExpiryCheck();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } on OdooException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error =
      'Impossible de joindre le serveur.\n'
          'Vérifiez:\n'
          '• L\'URL (ex: http://192.168.1.10:8069)\n'
          '• Que le téléphone et le serveur sont sur le même réseau WiFi\n'
          '• Que le port 8069 est accessible');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),

                  Icon(Icons.inventory_2_outlined,
                      size: 68, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Expiry Tracker',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Connectez-vous à votre serveur Odoo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),

                  const SizedBox(height: 32),

                  // ── Error banner ──────────────────────────────────────────
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                  height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── URL ───────────────────────────────────────────────────
                  TextFormField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'URL du serveur Odoo',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      helperText:
                      'Local: http://192.168.1.10:8069  •  Cloud: https://company.odoo.com',
                      helperMaxLines: 2,
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Requis';
                      if (!v.startsWith('http://') &&
                          !v.startsWith('https://')) {
                        return 'Doit commencer par http:// ou https://';
                      }
                      if (v == 'http://' || v == 'https://') {
                        return 'Entrez l\'adresse complète du serveur';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Database ──────────────────────────────────────────────
                  TextFormField(
                    controller: _dbCtrl,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Base de données',
                      hintText: 'nom_base',
                      prefixIcon: const Icon(Icons.storage_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      helperText:
                      'Visible sur la page de login Odoo (si une seule base, souvent le nom de la société)',
                      helperMaxLines: 2,
                    ),
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),

                  // ── Username ──────────────────────────────────────────────
                  TextFormField(
                    controller: _userCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Utilisateur',
                      hintText: 'admin ou email@societe.com',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requis' : null,
                  ),
                  const SizedBox(height: 16),

                  // ── Password ──────────────────────────────────────────────
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscurePass = !_obscurePass),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requis' : null,
                  ),

                  const SizedBox(height: 28),

                  // ── Login button ──────────────────────────────────────────
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                        : const Text('Se connecter',
                        style: TextStyle(fontSize: 16)),
                  ),

                  const SizedBox(height: 20),

                  // ── Network tip ───────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer
                          .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.wifi,
                            size: 16,
                            color: theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pour un serveur local, le téléphone et le serveur '
                                'Odoo doivent être sur le même réseau WiFi.',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSecondaryContainer,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}