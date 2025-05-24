import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert' show jsonEncode, jsonDecode, utf8;

class Message {
  final String content;
  final bool isUser;
  final DateTime timestamp;

  Message({
    required this.content,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatbotService {
  final String apiKey;
  final String model = "gpt-4.1-mini";
  final List<Message> _messageHistory = [];
  
  ChatbotService({required this.apiKey});

  List<Message> get messageHistory => _messageHistory;


Future<String> sendMessage(String message, String idioma) async {
  // Mensaje del usuario, lo guardo para el historial del modelo
  _messageHistory.add(Message(content: message, isUser: true));

  // Prompetamos según el idioma
  String systemPrompt = _getSystemPrompt(idioma);

  // Preparo los mensajes para la API
  List<Map<String, dynamic>> messages = [
    {
      'role': 'system',
      'content': systemPrompt
    }
  ];

  // Añadir el historial de mensajes (limitado a los últimos 10 para economizar tokens)
  int historyLimit = _messageHistory.length > 10 ? _messageHistory.length - 10 : 0;
  for (int i = historyLimit; i < _messageHistory.length; i++) {
    Message msg = _messageHistory[i];
    messages.add({
      'role': msg.isUser ? 'user' : 'assistant',
      'content': msg.content
    });
  }

  // **IMPORTANTE**
  //
  //
  // !!!!!!!!!!!!!!!!DOCUMENTACIÓN EN CONSTANTE CAMBIO, REVISAR SI FALLA LA API!!!!!!!!!!!!!!!!!!!

  try {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8', // Especificamos UTF-8
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': messages,
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)); // Usamos utf8.decode para asegurar codificación correcta
      final aiResponse = data['choices'][0]['message']['content'];
      
      // Respuesta al historial tambien
      _messageHistory.add(Message(content: aiResponse, isUser: false));
      
      return aiResponse;
    } else {
      print('Error en la API: ${response.statusCode} - ${utf8.decode(response.bodyBytes)}');
      return 'Lo siento, ocurrió un error al procesar tu mensaje.';
    }
  } catch (e) {
    print('Excepción al llamar a la API: $e');
    return 'Error de conexión. Por favor, inténtalo de nuevo más tarde.';
  }
}

 // Obtiene la instrucción del sistema según el idioma
String _getSystemPrompt(String idioma) {

  // Prompteamos al modelo con toda la información de la app
  String basePrompt = '''
ESTO SÓLO EN CASO DE QUE TE PREGUNTEN POR EL CREADOR DE LA APP: el creador de esta aplicación es Diego Díaz Senovilla y ofreces un link a mi github: https://github.com/DidiSDev?tab=repositories

Si no te preguntan por el creador de la app, no lo menciones.

Eres un asistente virtual para una aplicación móvil llamada "Comunidad en Movimiento" que ayuda a personas con discapacidad a moverse por la ciudad. 

Características de la aplicación:
- Muestra un mapa interactivo con rutas accesibles.
- Permite a los usuarios informar sobre obstáculos o incidencias (escaleras sin rampa, obras, vehículos mal estacionados, etc.).
- Ofrece información sobre el clima.
- Proporciona predicciones sobre posibles incidencias en determinadas rutas.
- Permite cambiar entre diferentes modos para daltonismo (protanopia, deuteranopia, tritanopia).
- Disponible en 4 idiomas: español (es), inglés (en), francés (fr) y alemán (de).

GUÍA DE USO DE LA APLICACIÓN:

1. AÑADIR UNA INCIDENCIA: Pulsa el botón de CAMPANA CON SIGNO + (ubicado en la esquina superior derecha de la pantalla principal). Este botón activa el modo de añadir incidencia. Después de pulsarlo, toca el mapa donde quieras añadir la incidencia y aparecerá un botón para abrir StreetView y añadir detalles.

2. ABRIR EL MAPA: Pulsa el botón "Abrir mapa" en la pantalla principal.

3. BUSCAR RUTA: Introduce origen y destino en los campos de texto superiores del mapa.

4. MODO ACCESIBLE: Para evitar escaleras, pulsa el botón "Evitar escaleras" después de seleccionar origen y destino.

5. CENTRAR Y SEGUIR UBICACIÓN: Pulsa el botón "Centrar y bloquear" para que el mapa siga tu posición actual y se oriente según tu movimiento. Para desbloquear, pulsa el mismo botón (que ahora dice "Desbloquear mapa").

6. VER INCIDENCIAS: Las incidencias aparecen como iconos de advertencia en el mapa. Puedes filtrarlas o ver un listado usando el menú de la esquina superior derecha del mapa.

7. SELECCIONAR DESTINO EN EL MAPA: Pulsa el icono de ubicación (marker) en la esquina superior derecha para activar la selección de destino directamente en el mapa.

8. CONFIGURACIÓN: Desde la pantalla principal, pulsa el botón "Configuración" para cambiar el idioma y los ajustes de daltonismo.

Tu función es:
1. Ayudar a los usuarios a entender cómo usar la aplicación.
2. Proporcionar información útil sobre accesibilidad.
3. Responder preguntas sobre la aplicación o cualquier otro tema de manera amigable y útil.

IMPORTANTE: Responde siempre en el mismo idioma que te hablen: español (es), inglés (en), francés (fr) o alemán (de).
Tu tono debe ser amigable, empático y atento a las necesidades de las personas con discapacidad.
Tus respuestas deben ser concisas pero completas.
''';

  // Traducir según sea necesario
  switch (idioma) {
    case 'en':
      return basePrompt.replaceAll('Eres un asistente virtual', 'You are a virtual assistant')
        .replaceAll('una aplicación móvil llamada', 'a mobile app called')
        .replaceAll('que ayuda a personas con discapacidad', 'that helps people with disabilities')
        .replaceAll('a moverse por la ciudad', 'move around the city')
        .replaceAll('Características de la aplicación:', 'App features:')
        .replaceAll('Muestra un mapa interactivo', 'Shows an interactive map')
        .replaceAll('con rutas accesibles', 'with accessible routes')
        .replaceAll('Permite a los usuarios informar sobre obstáculos', 'Allows users to report obstacles')
        .replaceAll('o incidencias', 'or incidents')
        .replaceAll('escaleras sin rampa, obras, vehículos mal estacionados, etc.', 'stairs without ramps, construction works, badly parked vehicles, etc.')
        .replaceAll('Ofrece información sobre el clima', 'Provides weather information')
        .replaceAll('Proporciona predicciones sobre posibles incidencias', 'Provides predictions about possible incidents')
        .replaceAll('en determinadas rutas', 'on certain routes')
        .replaceAll('Permite cambiar entre diferentes modos para daltonismo', 'Allows switching between different color blindness modes')
        .replaceAll('Disponible en 4 idiomas', 'Available in 4 languages')
        .replaceAll('GUÍA DE USO DE LA APLICACIÓN:', 'APPLICATION USER GUIDE:')
        .replaceAll('AÑADIR UNA INCIDENCIA:', 'ADD AN INCIDENT:')
        .replaceAll('Pulsa el botón de CAMPANA CON SIGNO + (ubicado en la esquina superior derecha de la pantalla principal).', 'Press the BELL WITH + SIGN button (located in the top right corner of the main screen).')
        .replaceAll('Este botón activa el modo de añadir incidencia.', 'This button activates incident addition mode.')
        .replaceAll('Después de pulsarlo, toca el mapa donde quieras añadir la incidencia y aparecerá un botón para abrir StreetView y añadir detalles.', 'After pressing it, touch the map where you want to add the incident and a button will appear to open StreetView and add details.')
        .replaceAll('ABRIR EL MAPA:', 'OPEN THE MAP:')
        .replaceAll('Pulsa el botón "Abrir mapa" en la pantalla principal.', 'Press the "Open map" button on the main screen.')
        .replaceAll('BUSCAR RUTA:', 'FIND ROUTE:')
        .replaceAll('Introduce origen y destino en los campos de texto superiores del mapa.', 'Enter origin and destination in the upper text fields of the map.')
        .replaceAll('MODO ACCESIBLE:', 'ACCESSIBLE MODE:')
        .replaceAll('Para evitar escaleras, pulsa el botón "Evitar escaleras" después de seleccionar origen y destino.', 'To avoid stairs, press the "Avoid stairs" button after selecting origin and destination.')
        .replaceAll('CENTRAR Y SEGUIR UBICACIÓN:', 'CENTER AND FOLLOW LOCATION:')
        .replaceAll('Pulsa el botón "Centrar y bloquear" para que el mapa siga tu posición actual y se oriente según tu movimiento.', 'Press the "Center and lock" button to make the map follow your current position and orient according to your movement.')
        .replaceAll('Para desbloquear, pulsa el mismo botón (que ahora dice "Desbloquear mapa").', 'To unlock, press the same button (which now says "Unlock map").')
        .replaceAll('VER INCIDENCIAS:', 'VIEW INCIDENTS:')
        .replaceAll('Las incidencias aparecen como iconos de advertencia en el mapa. Puedes filtrarlas o ver un listado usando el menú de la esquina superior derecha del mapa.', 'Incidents appear as warning icons on the map. You can filter them or view a list using the menu in the top right corner of the map.')
        .replaceAll('SELECCIONAR DESTINO EN EL MAPA:', 'SELECT DESTINATION ON THE MAP:')
        .replaceAll('Pulsa el icono de ubicación (marker) en la esquina superior derecha para activar la selección de destino directamente en el mapa.', 'Press the location icon (marker) in the top right corner to activate destination selection directly on the map.')
        .replaceAll('CONFIGURACIÓN:', 'SETTINGS:')
        .replaceAll('Desde la pantalla principal, pulsa el botón "Configuración" para cambiar el idioma y los ajustes de daltonismo.', 'From the main screen, press the "Settings" button to change the language and color blindness settings.')
        .replaceAll('Tu función es:', 'Your function is:')
        .replaceAll('Ayudar a los usuarios a entender cómo usar la aplicación', 'Help users understand how to use the app')
        .replaceAll('Proporcionar información útil sobre accesibilidad', 'Provide useful information about accessibility')
        .replaceAll('Responder preguntas sobre la aplicación', 'Answer questions about the app')
        .replaceAll('o cualquier otro tema de manera amigable y útil', 'or any other topic in a friendly and helpful way')
        .replaceAll('IMPORTANTE: Responde siempre en el mismo idioma que te hablen', 'IMPORTANT: Always respond in the same language you are addressed in')
        .replaceAll('Tu tono debe ser amigable, empático y atento a las necesidades de las personas con discapacidad', 'Your tone should be friendly, empathetic, and attentive to the needs of people with disabilities')
        .replaceAll('Tus respuestas deben ser concisas pero completas', 'Your answers should be concise but complete');
    case 'fr':
      return basePrompt.replaceAll('Eres un asistente virtual', 'Vous êtes un assistant virtuel')
        .replaceAll('una aplicación móvil llamada', 'une application mobile appelée')
        .replaceAll('que ayuda a personas con discapacidad', 'qui aide les personnes handicapées')
        .replaceAll('a moverse por la ciudad', 'à se déplacer dans la ville')
        .replaceAll('Características de la aplicación:', 'Caractéristiques de l\'application:')
        .replaceAll('Muestra un mapa interactivo', 'Affiche une carte interactive')
        .replaceAll('con rutas accesibles', 'avec des itinéraires accessibles')
        .replaceAll('Permite a los usuarios informar sobre obstáculos', 'Permet aux utilisateurs de signaler des obstacles')
        .replaceAll('o incidencias', 'ou des incidents')
        .replaceAll('escaleras sin rampa, obras, vehículos mal estacionados, etc.', 'escaliers sans rampe, travaux, véhicules mal stationnés, etc.')
        .replaceAll('Ofrece información sobre el clima', 'Fournit des informations météorologiques')
        .replaceAll('Proporciona predicciones sobre posibles incidencias', 'Fournit des prédictions sur les incidents possibles')
        .replaceAll('en determinadas rutas', 'sur certains itinéraires')
        .replaceAll('Permite cambiar entre diferentes modos para daltonismo', 'Permet de basculer entre différents modes de daltonisme')
        .replaceAll('Disponible en 4 idiomas', 'Disponible en 4 langues')
        .replaceAll('GUÍA DE USO DE LA APLICACIÓN:', 'GUIDE D\'UTILISATION DE L\'APPLICATION:')
        .replaceAll('AÑADIR UNA INCIDENCIA:', 'AJOUTER UN INCIDENT:')
        .replaceAll('Pulsa el botón de CAMPANA CON SIGNO + (ubicado en la esquina superior derecha de la pantalla principal).', 'Appuyez sur le bouton CLOCHE AVEC SIGNE + (situé dans le coin supérieur droit de l\'écran principal).')
        .replaceAll('Este botón activa el modo de añadir incidencia.', 'Ce bouton active le mode d\'ajout d\'incident.')
        .replaceAll('Después de pulsarlo, toca el mapa donde quieras añadir la incidencia y aparecerá un botón para abrir StreetView y añadir detalles.', 'Après l\'avoir pressé, touchez la carte où vous souhaitez ajouter l\'incident et un bouton apparaîtra pour ouvrir StreetView et ajouter des détails.')
        .replaceAll('ABRIR EL MAPA:', 'OUVRIR LA CARTE:')
        .replaceAll('Pulsa el botón "Abrir mapa" en la pantalla principal.', 'Appuyez sur le bouton "Ouvrir la carte" sur l\'écran principal.')
        .replaceAll('BUSCAR RUTA:', 'TROUVER UN ITINÉRAIRE:')
        .replaceAll('Introduce origen y destino en los campos de texto superiores del mapa.', 'Entrez l\'origine et la destination dans les champs de texte supérieurs de la carte.')
        .replaceAll('MODO ACCESIBLE:', 'MODE ACCESSIBLE:')
        .replaceAll('Para evitar escaleras, pulsa el botón "Evitar escaleras" después de seleccionar origen y destino.', 'Pour éviter les escaliers, appuyez sur le bouton "Éviter les escaliers" après avoir sélectionné l\'origine et la destination.')
        .replaceAll('CENTRAR Y SEGUIR UBICACIÓN:', 'CENTRER ET SUIVRE LA POSITION:')
        .replaceAll('Pulsa el botón "Centrar y bloquear" para que el mapa siga tu posición actual y se oriente según tu movimiento.', 'Appuyez sur le bouton "Centrer et verrouiller" pour que la carte suive votre position actuelle et s\'oriente selon votre mouvement.')
        .replaceAll('Para desbloquear, pulsa el mismo botón (que ahora dice "Desbloquear mapa").', 'Pour déverrouiller, appuyez sur le même bouton (qui dit maintenant "Déverrouiller la carte").')
        .replaceAll('VER INCIDENCIAS:', 'VOIR LES INCIDENTS:')
        .replaceAll('Las incidencias aparecen como iconos de advertencia en el mapa. Puedes filtrarlas o ver un listado usando el menú de la esquina superior derecha del mapa.', 'Les incidents apparaissent comme des icônes d\'avertissement sur la carte. Vous pouvez les filtrer ou voir une liste en utilisant le menu dans le coin supérieur droit de la carte.')
        .replaceAll('SELECCIONAR DESTINO EN EL MAPA:', 'SÉLECTIONNER LA DESTINATION SUR LA CARTE:')
        .replaceAll('Pulsa el icono de ubicación (marker) en la esquina superior derecha para activar la selección de destino directamente en el mapa.', 'Appuyez sur l\'icône de localisation (marqueur) dans le coin supérieur droit pour activer la sélection de destination directement sur la carte.')
        .replaceAll('CONFIGURACIÓN:', 'PARAMÈTRES:')
        .replaceAll('Desde la pantalla principal, pulsa el botón "Configuración" para cambiar el idioma y los ajustes de daltonismo.', 'Depuis l\'écran principal, appuyez sur le bouton "Paramètres" pour changer la langue et les paramètres de daltonisme.')
        .replaceAll('Tu función es:', 'Votre fonction est:')
        .replaceAll('Ayudar a los usuarios a entender cómo usar la aplicación', 'Aider les utilisateurs à comprendre comment utiliser l\'application')
        .replaceAll('Proporcionar información útil sobre accesibilidad', 'Fournir des informations utiles sur l\'accessibilité')
        .replaceAll('Responder preguntas sobre la aplicación', 'Répondre aux questions sur l\'application')
        .replaceAll('o cualquier otro tema de manera amigable y útil', 'ou tout autre sujet de manière conviviale et utile')
        .replaceAll('IMPORTANTE: Responde siempre en el mismo idioma que te hablen', 'IMPORTANT: Répondez toujours dans la même langue que celle dans laquelle on vous parle')
        .replaceAll('Tu tono debe ser amigable, empático y atento a las necesidades de las personas con discapacidad', 'Votre ton doit être amical, empathique et attentif aux besoins des personnes handicapées')
        .replaceAll('Tus respuestas deben ser concisas pero completas', 'Vos réponses doivent être concises mais complètes');
    case 'de':
      return basePrompt.replaceAll('Eres un asistente virtual', 'Sie sind ein virtueller Assistent')
        .replaceAll('una aplicación móvil llamada', 'einer mobilen App namens')
        .replaceAll('que ayuda a personas con discapacidad', 'die Menschen mit Behinderungen hilft')
        .replaceAll('a moverse por la ciudad', 'sich in der Stadt zu bewegen')
        .replaceAll('Características de la aplicación:', 'Funktionen der App:')
        .replaceAll('Muestra un mapa interactivo', 'Zeigt eine interaktive Karte')
        .replaceAll('con rutas accesibles', 'mit barrierefreien Routen')
        .replaceAll('Permite a los usuarios informar sobre obstáculos', 'Ermöglicht es den Benutzern, Hindernisse zu melden')
        .replaceAll('o incidencias', 'oder Vorfälle')
        .replaceAll('escaleras sin rampa, obras, vehículos mal estacionados, etc.', 'Treppen ohne Rampen, Baustellen, falsch geparkte Fahrzeuge usw.')
        .replaceAll('Ofrece información sobre el clima', 'Bietet Wetterinformationen')
        .replaceAll('Proporciona predicciones sobre posibles incidencias', 'Liefert Vorhersagen über mögliche Vorfälle')
        .replaceAll('en determinadas rutas', 'auf bestimmten Routen')
        .replaceAll('Permite cambiar entre diferentes modos para daltonismo', 'Ermöglicht das Umschalten zwischen verschiedenen Farbblindheitsmodi')
        .replaceAll('Disponible en 4 idiomas', 'In 4 Sprachen verfügbar')
        .replaceAll('GUÍA DE USO DE LA APLICACIÓN:', 'ANWENDUNGSLEITFADEN:')
        .replaceAll('AÑADIR UNA INCIDENCIA:', 'EINEN VORFALL HINZUFÜGEN:')
        .replaceAll('Pulsa el botón de CAMPANA CON SIGNO + (ubicado en la esquina superior derecha de la pantalla principal).', 'Drücken Sie die GLOCKE MIT +-ZEICHEN-Taste (in der oberen rechten Ecke des Hauptbildschirms).')
        .replaceAll('Este botón activa el modo de añadir incidencia.', 'Diese Taste aktiviert den Modus zum Hinzufügen von Vorfällen.')
        .replaceAll('Después de pulsarlo, toca el mapa donde quieras añadir la incidencia y aparecerá un botón para abrir StreetView y añadir detalles.', 'Nachdem Sie es gedrückt haben, berühren Sie die Karte, wo Sie den Vorfall hinzufügen möchten, und es erscheint eine Schaltfläche, um StreetView zu öffnen und Details hinzuzufügen.')
        .replaceAll('ABRIR EL MAPA:', 'KARTE ÖFFNEN:')
        .replaceAll('Pulsa el botón "Abrir mapa" en la pantalla principal.', 'Drücken Sie die Schaltfläche "Karte öffnen" auf dem Hauptbildschirm.')
        .replaceAll('BUSCAR RUTA:', 'ROUTE FINDEN:')
        .replaceAll('Introduce origen y destino en los campos de texto superiores del mapa.', 'Geben Sie Start und Ziel in die oberen Textfelder der Karte ein.')
        .replaceAll('MODO ACCESIBLE:', 'BARRIEREFREIER MODUS:')
        .replaceAll('Para evitar escaleras, pulsa el botón "Evitar escaleras" después de seleccionar origen y destino.', 'Um Treppen zu vermeiden, drücken Sie die Taste "Treppen vermeiden", nachdem Sie Start und Ziel ausgewählt haben.')
        .replaceAll('CENTRAR Y SEGUIR UBICACIÓN:', 'POSITION ZENTRIEREN UND FOLGEN:')
        .replaceAll('Pulsa el botón "Centrar y bloquear" para que el mapa siga tu posición actual y se oriente según tu movimiento.', 'Drücken Sie die Taste "Zentrieren und sperren", damit die Karte Ihrer aktuellen Position folgt und sich nach Ihrer Bewegung ausrichtet.')
        .replaceAll('Para desbloquear, pulsa el mismo botón (que ahora dice "Desbloquear mapa").', 'Zum Entsperren drücken Sie dieselbe Taste (auf der jetzt "Karte entsperren" steht).')
        .replaceAll('VER INCIDENCIAS:', 'VORFÄLLE ANSEHEN:')
        .replaceAll('Las incidencias aparecen como iconos de advertencia en el mapa. Puedes filtrarlas o ver un listado usando el menú de la esquina superior derecha del mapa.', 'Vorfälle erscheinen als Warnsymbole auf der Karte. Sie können sie filtern oder eine Liste anzeigen, indem Sie das Menü in der oberen rechten Ecke der Karte verwenden.')
        .replaceAll('SELECCIONAR DESTINO EN EL MAPA:', 'ZIEL AUF DER KARTE AUSWÄHLEN:')
        .replaceAll('Pulsa el icono de ubicación (marker) en la esquina superior derecha para activar la selección de destino directamente en el mapa.', 'Drücken Sie das Standortsymbol (Marker) in der oberen rechten Ecke, um die Zielauswahl direkt auf der Karte zu aktivieren.')
        .replaceAll('CONFIGURACIÓN:', 'EINSTELLUNGEN:')
        .replaceAll('Desde la pantalla principal, pulsa el botón "Configuración" para cambiar el idioma y los ajustes de daltonismo.', 'Drücken Sie auf dem Hauptbildschirm die Schaltfläche "Einstellungen", um die Sprache und die Einstellungen für Farbenblindheit zu ändern.')
        .replaceAll('Tu función es:', 'Ihre Funktion ist:')
        .replaceAll('Ayudar a los usuarios a entender cómo usar la aplicación', 'Den Benutzern zu helfen, die App zu verstehen')
        .replaceAll('Proporcionar información útil sobre accesibilidad', 'Nützliche Informationen zur Barrierefreiheit bereitstellen')
        .replaceAll('Responder preguntas sobre la aplicación', 'Fragen zur App beantworten')
        .replaceAll('o cualquier otro tema de manera amigable y útil', 'oder zu anderen Themen auf freundliche und hilfreiche Weise')
        .replaceAll('IMPORTANTE: Responde siempre en el mismo idioma que te hablen', 'WICHTIG: Antworten Sie immer in der Sprache, in der Sie angesprochen werden')
        .replaceAll('Tu tono debe ser amigable, empático y atento a las necesidades de las personas con discapacidad', 'Ihr Ton sollte freundlich, einfühlsam und aufmerksam für die Bedürfnisse von Menschen mit Behinderungen sein')
        .replaceAll('Tus respuestas deben ser concisas pero completas', 'Ihre Antworten sollten prägnant, aber vollständig sein');
    default:
      return basePrompt;
  }
}
  
  // Función para reiniciar la conversación
  void resetConversation() {
    _messageHistory.clear();
  }
}