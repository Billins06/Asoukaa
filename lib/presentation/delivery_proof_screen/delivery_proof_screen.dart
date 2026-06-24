import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:sizer/sizer.dart';

import 'package:dio/dio.dart';

import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class DeliveryProofScreen extends StatefulWidget {
  final Map<String, dynamic>? deliveryData;
  const DeliveryProofScreen({super.key, this.deliveryData});

  @override
  State<DeliveryProofScreen> createState() => _DeliveryProofScreenState();
}

class _DeliveryProofScreenState extends State<DeliveryProofScreen>
    with TickerProviderStateMixin {
  // Step management
  int _currentStep = 0;
  final int _totalSteps = 5;

  // QR Scanner state
  bool _qrScanned = false;
  bool _isScannerActive = false;
  String _scannedQrCode = '';
  MobileScannerController? _scannerController;

  // Photo state
  bool _photoTaken = false;
  String _photoUrl = '';
  bool _isUploadingPhoto = false;

  // Notes state
  final TextEditingController _notesController = TextEditingController();
  String _selectedCondition = 'Bon état';
  final List<String> _conditions = [
    'Bon état',
    'Légèrement endommagé',
    'Endommagé',
    'Refusé par le client',
  ];

  // GPS tracking state
  bool _gpsStarted = false;
  Position? _currentPosition;
  bool _isLoadingGps = false;
  String _gpsStatusText = 'Appuyez pour démarrer le suivi GPS';

  // Signature state
  bool _signatureConfirmed = false;
  bool _isDrawing = false;
  final List<List<Offset>> _signatureStrokes = [];
  List<Offset> _currentStroke = [];
  late AnimationController _successController;
  late Animation<double> _successAnimation;

  // Submission state
  bool _isSubmitting = false;
  bool _submitted = false;

  final Map<String, dynamic> _mockDelivery = {
    'id': 'CMD-2847',
    'client': 'Aminata Sow',
    'phone': '+221 77 456 78 90',
    'address': 'Almadies, Villa 14, Dakar',
    'items': '3 articles',
    'weight': '4.2 kg',
    'amount': '18 500 FCFA',
    'qrCode': 'ASK-2847-ALMADIES-2026',
  };

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );
    }
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnimation = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _successController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _delivery => widget.deliveryData ?? _mockDelivery;

  // ── QR Scanner ─────────────────────────────────────────────────────────

  void _startScanner() {
    if (kIsWeb) {
      _showManualQrEntry();
      return;
    }
    setState(() {
      _isScannerActive = true;
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    });
  }

  void _stopScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    setState(() => _isScannerActive = false);
  }

  void _onQrDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final code = barcodes.first.rawValue ?? '';
    if (code.isEmpty) return;
    _stopScanner();
    setState(() {
      _qrScanned = true;
      _scannedQrCode = code;
    });
    HapticFeedback.mediumImpact();
  }

  void _showManualQrEntry() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Saisir le code manuellement',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.outfit(),
          decoration: InputDecoration(
            hintText: 'Ex: ASK-2847-DAKAR-2026',
            hintStyle: GoogleFonts.outfit(color: AppTheme.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.outfit()),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                setState(() {
                  _qrScanned = true;
                  _scannedQrCode = code;
                });
                HapticFeedback.mediumImpact();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text('Valider', style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }

  // ── Photo ──────────────────────────────────────────────────────────────

  Future<void> _captureDeliveryPhoto({
    ImageSource source = ImageSource.camera,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1200, imageQuality: 80);
    if (picked == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final fileName = 'delivery_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });
      final res = await ApiService.instance.client.post('/api/v1/uploads/image', data: formData);
      final url = res.data['url'] as String?;
      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        if (url != null) {
          _photoTaken = true;
          _photoUrl = url;
          HapticFeedback.lightImpact();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Échec de l\'upload. Réessayez.', style: GoogleFonts.outfit()),
              backgroundColor: AppTheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec de l\'upload. Réessayez.', style: GoogleFonts.outfit()),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('Appareil photo', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _captureDeliveryPhoto(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Galerie', style: GoogleFonts.outfit()),
              onTap: () {
                Navigator.pop(ctx);
                _captureDeliveryPhoto(source: ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── GPS ────────────────────────────────────────────────────────────────

  Future<void> _startGpsTracking() async {
    setState(() {
      _isLoadingGps = true;
      _gpsStatusText = 'Obtention de la position...';
    });

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _isLoadingGps = false;
        _gpsStatusText = 'Service GPS désactivé. Activez la localisation.';
      });
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _isLoadingGps = false;
        _gpsStatusText = 'Permission GPS refusée. Activez la localisation.';
      });
      return;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      position = null;
    }
    if (!mounted) return;

    if (position != null) {
      setState(() {
        _gpsStarted = true;
        _currentPosition = position;
        _isLoadingGps = false;
        _gpsStatusText =
            'Suivi actif — ${position!.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      });
      HapticFeedback.mediumImpact();
    } else {
      setState(() {
        _isLoadingGps = false;
        _gpsStatusText = 'Impossible d\'obtenir la position. Réessayez.';
      });
    }
  }

  // ── Signature ──────────────────────────────────────────────────────────

  void _clearSignature() {
    setState(() {
      _signatureStrokes.clear();
      _currentStroke.clear();
      _signatureConfirmed = false;
    });
  }

  void _confirmSignature() {
    if (_signatureStrokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Veuillez signer avant de confirmer',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _signatureConfirmed = true);
    _successController.forward();
    HapticFeedback.mediumImpact();
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _qrScanned;
      case 1:
        return _photoTaken;
      case 2:
        return true;
      case 3:
        return _gpsStarted;
      case 4:
        return _signatureConfirmed;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _submitProof();
    }
  }

  void _submitProof() async {
    setState(() => _isSubmitting = true);
    try {
      final orderId = _delivery['id'] ?? '';
      if (orderId.isNotEmpty) {
        await ApiService.instance.client.patch(
          '/api/v1/orders/$orderId/delivery-proof',
          data: {
            'proofPhotoUrl': _photoUrl,
            'deliveryCondition': _selectedCondition,
            'deliveryNotes': _notesController.text.trim(),
            'qrCodeScanned': _scannedQrCode,
            'signatureConfirmed': _signatureConfirmed,
            'gpsLat': _currentPosition?.latitude,
            'gpsLng': _currentPosition?.longitude,
          },
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitted = true;
    });
    HapticFeedback.heavyImpact();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccessView();
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: _buildCurrentStep(),
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () {
          if (_isScannerActive) {
            _stopScanner();
            return;
          }
          if (_currentStep > 0) {
            setState(() => _currentStep--);
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preuve de livraison',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            _delivery['id'] ?? 'CMD-2847',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primaryMuted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_currentStep + 1}/$_totalSteps',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final stepLabels = ['QR Code', 'Photo', 'Notes', 'GPS', 'Signature'];
    final stepIcons = [
      Icons.qr_code_scanner_rounded,
      Icons.camera_alt_rounded,
      Icons.edit_note_rounded,
      Icons.location_on_rounded,
      Icons.draw_rounded,
    ];
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final isCompleted = i < _currentStep;
          final isActive = i == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCompleted
                              ? AppTheme.success
                              : isActive
                              ? AppTheme.primary
                              : AppTheme.outlineVariant,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCompleted ? Icons.check_rounded : stepIcons[i],
                          size: 15,
                          color: isCompleted || isActive
                              ? Colors.white
                              : AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepLabels[i],
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isActive
                              ? AppTheme.primary
                              : isCompleted
                              ? AppTheme.success
                              : AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < _totalSteps - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: i < _currentStep
                            ? AppTheme.success
                            : AppTheme.outlineVariant,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildQrStep();
      case 1:
        return _buildPhotoStep();
      case 2:
        return _buildNotesStep();
      case 3:
        return _buildGpsStep();
      case 4:
        return _buildSignatureStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(4.w, 12, 4.w, 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: (_canProceed && !_isSubmitting) ? _nextStep : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.outlineVariant,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.0),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  _currentStep == _totalSteps - 1
                      ? 'Soumettre la preuve'
                      : 'Continuer',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  // ─── STEP 1: QR SCANNER ───────────────────────────────────────────────

  Widget _buildQrStep() {
    final expectedQrCode = _delivery['qrCode'] as String? ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDeliveryInfoCard(),
          const SizedBox(height: 16),
          if (expectedQrCode.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.qr_code_2_rounded,
                          color: AppTheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QR Code de la commande',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Présentez ce code au client',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: PrettyQrView.data(
                          data: expectedQrCode,
                          decoration: const PrettyQrDecoration(
                            shape: PrettyQrSmoothSymbol(
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          errorCorrectLevel: QrErrorCorrectLevel.M,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      expectedQrCode,
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Scanner le QR Code client',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 220,
                    child: _qrScanned
                        ? _buildQrSuccess()
                        : _isScannerActive
                        ? _buildActiveScannerView()
                        : _buildScannerPlaceholder(),
                  ),
                ),
                if (_qrScanned) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          color: AppTheme.success,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _scannedQrCode,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _qrScanned = false;
                            _scannedQrCode = '';
                          }),
                          child: const Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!_qrScanned) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isScannerActive
                              ? _stopScanner
                              : _startScanner,
                          icon: Icon(
                            _isScannerActive
                                ? Icons.stop_rounded
                                : Icons.qr_code_scanner_rounded,
                            size: 18,
                          ),
                          label: Text(
                            _isScannerActive ? 'Arrêter' : 'Scanner',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isScannerActive
                                ? AppTheme.error
                                : AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      if (!_isScannerActive) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _showManualQrEntry,
                          icon: const Icon(Icons.keyboard_rounded, size: 16),
                          label: Text(
                            'Manuel',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveScannerView() {
    return Stack(
      children: [
        MobileScanner(controller: _scannerController!, onDetect: _onQrDetected),
        Positioned.fill(child: CustomPaint(painter: _QrCornerPainter())),
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(153),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Pointez vers le QR Code',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScannerPlaceholder() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_2_rounded,
            size: 48,
            color: Colors.white.withAlpha(77),
          ),
          const SizedBox(height: 8),
          Text(
            'Appuyez sur "Scanner" pour démarrer',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.white.withAlpha(128),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSuccess() {
    return Container(
      color: AppTheme.successContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.success.withAlpha(38),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.success,
              size: 32,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'QR Code validé !',
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Commande vérifiée avec succès',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 2: PHOTO CAPTURE ────────────────────────────────────────────

  Widget _buildPhotoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Photo du colis',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Photographiez le colis livré',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: (_isUploadingPhoto || _photoTaken)
                      ? null
                      : _showPhotoSourceDialog,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 240,
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _photoTaken
                            ? AppTheme.success
                            : AppTheme.outline,
                        width: _photoTaken ? 2 : 1,
                      ),
                    ),
                    child: _isUploadingPhoto
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.primary,
                            ),
                          )
                        : _photoTaken
                        ? _buildPhotoPreview()
                        : _buildCameraPlaceholder(),
                  ),
                ),
                if (_photoTaken) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _photoTaken = false;
                            _photoUrl = '';
                          }),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            'Reprendre',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.successContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.success,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Photo validée',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warningContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withAlpha(77)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.warning,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Assurez-vous que le colis et l\'adresse de livraison sont visibles sur la photo.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.outlineVariant,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.camera_alt_outlined,
            size: 28,
            color: AppTheme.muted,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Prendre une photo',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Appuyez pour capturer',
          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.muted),
        ),
      ],
    );
  }

  Widget _buildPhotoPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _photoUrl,
            fit: BoxFit.cover,
            semanticLabel: 'Photo du colis livré à l\'adresse du client',
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.success,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Capturée',
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 3: DELIVERY NOTES ───────────────────────────────────────────

  Widget _buildNotesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Notes de livraison',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'État du colis',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _conditions.map((condition) {
                    final isSelected = _selectedCondition == condition;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCondition = condition),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          condition,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Remarques (optionnel)',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  style: GoogleFonts.outfit(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ex: Colis laissé chez le voisin...',
                    hintStyle: GoogleFonts.outfit(
                      color: AppTheme.muted,
                      fontSize: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppTheme.outlineVariant,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: AppTheme.outlineVariant,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                    filled: true,
                    fillColor: AppTheme.background,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 4: GPS TRACKING ─────────────────────────────────────────────

  Widget _buildGpsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _gpsStarted
                            ? AppTheme.successContainer
                            : AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: _gpsStarted
                            ? AppTheme.success
                            : AppTheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Suivi GPS en temps réel',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Partagez votre position pour la livraison',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_gpsStarted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.successContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppTheme.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Actif',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _gpsStarted
                        ? AppTheme.successContainer
                        : AppTheme.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _gpsStarted
                          ? AppTheme.success.withAlpha(100)
                          : AppTheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _gpsStarted
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded,
                        size: 48,
                        color: _gpsStarted ? AppTheme.success : AppTheme.muted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _gpsStarted
                            ? 'Position enregistrée'
                            : 'GPS non démarré',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _gpsStarted
                              ? AppTheme.success
                              : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _gpsStatusText,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      if (_currentPosition != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildCoordChip(
                              'Lat',
                              _currentPosition!.latitude.toStringAsFixed(5),
                            ),
                            const SizedBox(width: 8),
                            _buildCoordChip(
                              'Lng',
                              _currentPosition!.longitude.toStringAsFixed(5),
                            ),
                          ],
                        ),
                        if (_currentPosition!.accuracy > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Précision: ${_currentPosition!.accuracy.toStringAsFixed(0)} m',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!_gpsStarted)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingGps ? null : _startGpsTracking,
                      icon: _isLoadingGps
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, size: 18),
                      label: Text(
                        _isLoadingGps
                            ? 'Localisation...'
                            : 'Démarrer le suivi GPS',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                if (_gpsStarted)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final pos = await Geolocator.getCurrentPosition(
                            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
                          );
                          if (mounted) {
                            setState(() {
                              _currentPosition = pos;
                              _gpsStatusText =
                                  '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
                            });
                          }
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        'Actualiser la position',
                        style: GoogleFonts.outfit(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Votre position GPS est partagée en temps réel avec le client pour un suivi transparent de la livraison.',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(fontSize: 9, color: AppTheme.muted),
          ),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── STEP 5: SIGNATURE ────────────────────────────────────────────────

  Widget _buildSignatureStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.draw_rounded,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Signature de réception',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'Le client confirme la réception',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: AppTheme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_signatureConfirmed) ...[
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.outline),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GestureDetector(
                        onPanStart: (d) {
                          setState(() {
                            _isDrawing = true;
                            _currentStroke = [d.localPosition];
                          });
                        },
                        onPanUpdate: (d) {
                          setState(() => _currentStroke.add(d.localPosition));
                        },
                        onPanEnd: (_) {
                          setState(() {
                            if (_currentStroke.isNotEmpty) {
                              _signatureStrokes.add(List.from(_currentStroke));
                            }
                            _currentStroke = [];
                            _isDrawing = false;
                          });
                        },
                        child: CustomPaint(
                          painter: _SignaturePainter(
                            strokes: _signatureStrokes,
                            currentStroke: _currentStroke,
                          ),
                          child: Container(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clearSignature,
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          label: Text(
                            'Effacer',
                            style: GoogleFonts.outfit(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _confirmSignature,
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            'Confirmer',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  ScaleTransition(
                    scale: _successAnimation,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.successContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AppTheme.success,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Signature confirmée',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── DELIVERY INFO CARD ───────────────────────────────────────────────

  Widget _buildDeliveryInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6210), Color(0xFFFF8C42)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _delivery['client'] ?? 'Client',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _delivery['address'] ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _delivery['amount'] ?? '',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(
                Icons.inventory_2_rounded,
                _delivery['items'] ?? '',
              ),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.scale_rounded, _delivery['weight'] ?? ''),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.phone_rounded, _delivery['phone'] ?? ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: AppTheme.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SUCCESS VIEW ─────────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.successContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.success,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Livraison confirmée !',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'La preuve de livraison a été soumise avec succès.',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Retour au tableau de bord',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  _SignaturePainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.length >= 2) {
      final path = Path()
        ..moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (int i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

class _QrCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLen = 24.0;
    const margin = 40.0;

    final corners = [
      [
        Offset(margin, margin + cornerLen),
        Offset(margin, margin),
        Offset(margin + cornerLen, margin),
      ],
      [
        Offset(size.width - margin - cornerLen, margin),
        Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + cornerLen),
      ],
      [
        Offset(margin, size.height - margin - cornerLen),
        Offset(margin, size.height - margin),
        Offset(margin + cornerLen, size.height - margin),
      ],
      [
        Offset(size.width - margin - cornerLen, size.height - margin),
        Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin, size.height - margin - cornerLen),
      ],
    ];

    for (final corner in corners) {
      final path = Path()
        ..moveTo(corner[0].dx, corner[0].dy)
        ..lineTo(corner[1].dx, corner[1].dy)
        ..lineTo(corner[2].dx, corner[2].dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_QrCornerPainter old) => false;
}
