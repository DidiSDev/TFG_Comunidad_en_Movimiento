import 'package:flutter/material.dart';
import 'package:comunidad_en_movimiento/services/chatbot_service.dart';
import 'traducciones.dart';
import 'colores_personalizados.dart';

class ChatbotWidget extends StatefulWidget {
  final String modoDaltonismo;
  final String idiomaSeleccionado;
  final ChatbotService chatbotService;
  final Function(bool) onExpandedChanged; // Callback para notificar cambios y actualiozar

  const ChatbotWidget({
    Key? key,
    required this.modoDaltonismo,
    required this.idiomaSeleccionado,
    required this.chatbotService,
    required this.onExpandedChanged,
  }) : super(key: key);

  @override
  _ChatbotWidgetState createState() => _ChatbotWidgetState();
}

class _ChatbotWidgetState extends State<ChatbotWidget> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _heightAnimation;
  bool _isLoading = false;
  String _agentName = "Agente Nova"; // Nombre del agente (se lo ha puesto a sí mismo) 
  // De momento cambio y dejo "Asistente IA"

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heightAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Agregamos un mensaje inicial del asistente si no hay mensajes previos
    if (widget.chatbotService.messageHistory.isEmpty) {
      _addInitialMessage();
    }
  }

  // Suu primer mensaje en función del idioma detectado en config
  void _addInitialMessage() {
    String mensaje = 'Estoy aquí para ayudarte';
    switch (widget.idiomaSeleccionado) {
      case 'en':
        mensaje = 'I\'m here to help you';
        break;
      case 'fr':
        mensaje = 'Je suis là pour vous aider';
        break;
      case 'de':
        mensaje = 'Ich bin hier, um zu helfen';
        break;
      default:
        mensaje = 'Estoy aquí para ayudarte';
    }
    
    widget.chatbotService.messageHistory.add(
      Message(content: mensaje, isUser: false)
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleChatExpansion() {
  setState(() {
    _isExpanded = !_isExpanded;
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
    
    // Notificar al widget padre sobre el cambio
    widget.onExpandedChanged(_isExpanded);
  });
}

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    _messageController.clear();
    // El mensaje del usuario se añade dentro de sendMessage
    await widget.chatbotService.sendMessage(text, widget.idiomaSeleccionado);

    setState(() {
      _isLoading = false;
    });

    // Hacemos scroll hasta el final después de recibir la respuesta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

@override
Widget build(BuildContext context) {
  // Calculamos una altura fija más pequeña para el chat
  final screenHeight = MediaQuery.of(context).size.height;
  // Altura máxima: reducida para evitar problemas con el teclado
  final maxChatHeight = screenHeight * 0.45; // 45% de la altura de la pantalla
  
  // Traducción del nombre del agente según el idioma
  String agentTitle;
  switch (widget.idiomaSeleccionado) {
    case 'en':
      agentTitle = "AI Assistant";
      break;
    case 'fr':
      agentTitle = "Assistant IA";
      break;
    case 'de':
      agentTitle = "KI-Assistent";
      break;
    default:
      agentTitle = "Asistente IA";
  }

  return Column(
    mainAxisSize: MainAxisSize.min, // Aseguramos que ocupe el mínimo espacio
    children: [
      // Botón para expandir/colapsar el chat
      InkWell(
        onTap: _toggleChatExpansion,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: obtenerColorBoton(widget.modoDaltonismo),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono que cambia según el estado
              Icon(
                _isExpanded 
                  ? Icons.close_rounded 
                  : Icons.smart_toy_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                _isExpanded
                  ? traducir('Cerrar asistente', widget.idiomaSeleccionado)
                  : agentTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      
      // Contenedor animado del chat (solo visible cuando está expandido)
      AnimatedBuilder(
        animation: _heightAnimation,
        builder: (context, child) {
          return SizedBox(
            height: _heightAnimation.value * maxChatHeight,
            child: Opacity(
              opacity: _heightAnimation.value,
              child: child,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Mejor min?
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              // Cabecera del chat
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: obtenerColorBoton(widget.modoDaltonismo).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_rounded,
                      color: obtenerColorBoton(widget.modoDaltonismo),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      agentTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: obtenerColorBoton(widget.modoDaltonismo),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Lista de mensajes
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: widget.chatbotService.messageHistory.length,
                  itemBuilder: (context, index) {
                    final message = widget.chatbotService.messageHistory[index];
                    return _buildMessageBubble(message);
                  },
                ),
              ),
              
              // Indicador de carga
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      obtenerColorBoton(widget.modoDaltonismo),
                    ),
                  ),
                ),
              
              // Campo de entrada de mensaje (simplificado, sin ajuste de teclado)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: traducir('Escribe tu mensaje...', widget.idiomaSeleccionado),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      // Limitamos a una sola línea para reducir altura
                      maxLines: 1,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      Icons.send,
                      color: obtenerColorBoton(widget.modoDaltonismo),
                    ),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

// Modificación para agregar resizing con el teclado
Widget _buildTextField() {
  return Padding(
    padding: EdgeInsets.only(
      bottom: MediaQuery.of(context).viewInsets.bottom, // Esto debería ajustar el padding según el tamaño del teclado pero no funciona correctamente
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _messageController,
            decoration: InputDecoration(
              hintText: traducir('Escribe tu mensaje...', widget.idiomaSeleccionado),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            // Permitimos múltiples líneas y scroll automático
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            // Fuerzo el enfoque cuando se expande el chatbot
            focusNode: FocusNode()..requestFocus(),
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            Icons.send,
            color: obtenerColorBoton(widget.modoDaltonismo),
          ),
          onPressed: _sendMessage,
        ),
      ],
    ),
  );
}

  Widget _buildMessageBubble(Message message) {
    return Align(
      alignment: message.isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: message.isUser
              ? obtenerColorBoton(widget.modoDaltonismo).withOpacity(0.8)
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}