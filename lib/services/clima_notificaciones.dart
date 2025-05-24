import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:comunidad_en_movimiento/home/traducciones.dart';

class ClimaNotificaciones {
  static final ClimaNotificaciones _instance = ClimaNotificaciones._internal();
  factory ClimaNotificaciones() => _instance;
  ClimaNotificaciones._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = 
      FlutterLocalNotificationsPlugin();
  Timer? _checkTimer;
  bool _isInitialized = false;
  String _currentLanguage = 'es';

  // Registra las condiciones peligrosas ya notificadas para evitar notificaciones repetidas
  final Map<String, DateTime> _notifiedConditions = {};

  Future<void> initialize(String language) async {
    _currentLanguage = language;
    
    if (_isInitialized) return;
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    
    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
    );
    
    _isInitialized = true;
  }

  void startMonitoring(double latitude, double longitude, String language) {
    _currentLanguage = language;
    
    // Cancelar el timer anterior si existe
    _checkTimer?.cancel();
    
    // Iniciar un nuevo timer para verificar alertas cada 30 minutos
    _checkTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
      checkWeatherAlerts(latitude, longitude);
    });
    
    // Verificar inmediatamente al inicio
    checkWeatherAlerts(latitude, longitude);
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> checkWeatherAlerts(double latitude, double longitude) async {
    if (!_isInitialized) await initialize(_currentLanguage);
    
    try {
      // URL de la API con alertas meteorológicas (TAMBIEN EN CONSTANTE CAMBIO, REVISAR DOCS SI FALLA, el código no es)
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?'
        'latitude=$latitude&longitude=$longitude&'
        'daily=weathercode,temperature_2m_max,temperature_2m_min&'
        'current_weather=true&'
        'timezone=auto&'
        'forecast_days=3'
      );

      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Analizar condiciones actuales
        final currentWeather = data['current_weather'];
        final weatherCode = currentWeather['weathercode'];
        final temperature = currentWeather['temperature'];
        
        // Analizar pronóstico
        final daily = data['daily'];
        final dailyCodes = daily['weathercode'] as List;
        final maxTemps = daily['temperature_2m_max'] as List;
        
        // Verificar condiciones peligrosas
        _checkDangerousConditions(weatherCode, temperature, dailyCodes, maxTemps);
      }
    } catch (e) {
      print('Error al verificar alertas meteorológicas: $e');
    }
  }

  void _checkDangerousConditions(
    int currentCode, 
    double currentTemp,
    List dailyCodes,
    List maxTemps
  ) {
    // Verificar tormentas actuales (códigos 95-99)
    if (currentCode >= 95 && currentCode <= 99) {
      _showNotification(
        'alerta_tormenta',
        traducir('Alerta de Tormenta', _currentLanguage),
        traducir('Hay una tormenta fuerte en tu ubicación actual. Permanece en interiores.', _currentLanguage),
      );
    }
    
    // Verificar tormentas futuras
    for (int i = 0; i < dailyCodes.length; i++) {
      if (dailyCodes[i] >= 95 && dailyCodes[i] <= 99) {
        _showNotification(
          'alerta_tormenta_futura_$i',
          traducir('Alerta de Tormenta', _currentLanguage),
          traducir('Se prevé una tormenta fuerte en los próximos días.', _currentLanguage),
        );
        break;
      }
    }
    
    // Verificar olas de calor (temperatura > 35°C)
    if (currentTemp > 35) {
      _showNotification(
        'alerta_calor',
        traducir('Alerta de Calor', _currentLanguage),
        traducir('Temperatura muy elevada. Evita la exposición al sol y mantente hidratado.', _currentLanguage),
      );
    }
    
    // Verificar olas de calor futuras
    for (int i = 0; i < maxTemps.length; i++) {
      if (maxTemps[i] > 35) {
        _showNotification(
          'alerta_calor_futura_$i',
          traducir('Alerta de Calor', _currentLanguage),
          traducir('Se prevé una ola de calor en los próximos días.', _currentLanguage),
        );
        break;
      }
    }
    
    // Verificar nieve o hielo (códigos 70-79)
    if (currentCode >= 70 && currentCode <= 79) {
      _showNotification(
        'alerta_nieve',
        traducir('Alerta de Nieve', _currentLanguage),
        traducir('Condiciones de nieve o hielo. Ten precaución al caminar o conducir.', _currentLanguage),
      );
    }
  }

  Future<void> _showNotification(String id, String title, String body) async {
    // Evitar notificaciones repetidas en el mismo día
    final now = DateTime.now();
    final lastNotified = _notifiedConditions[id];
    
    if (lastNotified != null) {
      final difference = now.difference(lastNotified);
      if (difference.inHours < 12) return; // No notificar si ya se hizo en las últimas 12 horas
    }
    
    _notifiedConditions[id] = now;
    
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'weather_alerts',
      'Alertas Meteorológicas',
      channelDescription: 'Alertas sobre condiciones meteorológicas peligrosas',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _flutterLocalNotificationsPlugin.show(
      id.hashCode,
      title,
      body,
      platformChannelSpecifics,
    );
  }
}