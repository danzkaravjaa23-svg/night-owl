import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'host_badge_inset.dart' show hostBadgeMaxHeight;

/// Хостинг (Netlify free plan) хуудсанд өөрөө оруулдаг "Powered by ..."
/// badge-ийн байрлалыг зөвхөн УНШИНА. Тэр элемент рүү хэзээ ч бичихгүй,
/// нуухгүй, хөдөлгөхгүй — апп өөрөө доороо зай үлдээхэд л ашиглана.
final ValueNotifier<Rect?> _rect = ValueNotifier<Rect?>(null);
bool _started = false;
Timer? _timer;
int _step = 0;

// Badge script async ачаалагдаж, iframe-ийг хожуу нэмээд хэмжээгээ
// өөрчилдөг тул эхний минутад олон удаа шалгана. Дараа нь badge-ийн карт
// нээгдэж/хаагдах, badge нуугдах зэргийг алдахгүйн тулд [_idleCheck] тутам
// хямдхан (зөвхөн уншдаг) шалгалт үргэлжилнэ.
const Duration _idleCheck = Duration(seconds: 2);
const List<int> _delaysMs = [
  300, 700, 1200, 2000, 3000, 4500, 6500, 9000, 13000, 20000, 30000, 45000,
  60000,
];

ValueListenable<Rect?> get hostBadgeRect {
  if (!_started) {
    _started = true;
    try {
      // Badge script-ийн tag-ийг хостинг HTML-д өөрөө бичдэг тул апп
      // эхлэхэд аль хэдийн байна. Байхгүй бол (локал, өөр хостинг) ямар ч
      // timer, listener эхлүүлэхгүй — зай үргэлж 0.
      if (_hostScriptPresent()) {
        _check();
        _schedule(restart: true);
        globalContext.callMethod<JSAny?>(
            'addEventListener'.toJS, 'resize'.toJS, _onResize.toJS);
      }
    } catch (_) {
      // Ямар нэг шалтгаанаар уншиж чадахгүй бол badge байхгүй гэж үзнэ.
    }
  }
  return _rect;
}

bool _hostScriptPresent() {
  final document = globalContext['document'] as JSObject?;
  if (document == null) return false;
  return document.callMethod<JSAny?>(
          'querySelector'.toJS, 'script[data-nf-variant]'.toJS) !=
      null;
}

void _onResize(JSAny? _) {
  _check();
  _schedule(restart: true);
}

void _schedule({bool restart = false}) {
  if (restart) {
    _timer?.cancel();
    _step = 0;
  }
  if (_step >= _delaysMs.length) {
    _timer = Timer.periodic(_idleCheck, (_) => _check());
    return;
  }
  final prev = _step == 0 ? 0 : _delaysMs[_step - 1];
  final wait = _delaysMs[_step] - prev;
  _step++;
  _timer = Timer(Duration(milliseconds: wait), () {
    _check();
    _schedule();
  });
}

void _check() {
  Rect? next;
  try {
    next = _findBadge();
  } catch (_) {
    next = null;
  }
  // Badge-ийн "Powered by" карт нээлттэй үед iframe өндөр болдог — тэр
  // үеийн хэмжээг badge гэж авахгүй, өмнөх зөв хэмжээг хадгална. Карт
  // хаагдахад дараагийн шалгалт жинхэнэ badge-ийг дахин олно.
  if (next != null && next.height > hostBadgeMaxHeight) return;
  if (next != _rect.value) _rect.value = next;
}

double? _num(JSObject o, String key) => (o[key] as JSNumber?)?.toDartDouble;

Rect? _findBadge() {
  final document = globalContext['document'] as JSObject?;
  if (document == null) return null;
  // 1) Хостингийн badge script-ийн tag байх ёстой.
  final script = document.callMethod<JSAny?>(
      'querySelector'.toJS, 'script[data-nf-variant]'.toJS);
  if (script == null) return null;
  final body = document['body'] as JSObject?;
  if (body == null) return null;
  final children = body['children'] as JSObject?;
  if (children == null) return null;
  final innerWidth = _num(globalContext, 'innerWidth');
  final innerHeight = _num(globalContext, 'innerHeight');
  if (innerWidth == null || innerHeight == null) return null;
  final count = _num(children, 'length')?.toInt() ?? 0;
  // 2) body-ийн шууд хүүхэд, position:fixed, баруун доод буланд наалдсан iframe.
  for (var i = count - 1; i >= 0; i--) {
    final el = children.callMethod<JSAny?>('item'.toJS, i.toJS) as JSObject?;
    if (el == null) continue;
    final tag = (el['tagName'] as JSString?)?.toDart.toUpperCase();
    if (tag != 'IFRAME') continue;
    final style = globalContext.callMethod<JSAny?>(
        'getComputedStyle'.toJS, el) as JSObject?;
    final position = (style?['position'] as JSString?)?.toDart;
    if (position != 'fixed') continue;
    final box = el.callMethod<JSAny?>('getBoundingClientRect'.toJS)
        as JSObject?;
    if (box == null) continue;
    final left = _num(box, 'left');
    final top = _num(box, 'top');
    final right = _num(box, 'right');
    final bottom = _num(box, 'bottom');
    if (left == null || top == null || right == null || bottom == null) {
      continue;
    }
    if (right - left <= 0 || bottom - top <= 0) continue; // нуугдсан
    const tolerance = 24.0;
    if (innerWidth - right > tolerance) continue;
    if (innerHeight - bottom > tolerance) continue;
    return Rect.fromLTRB(left, top, right, bottom);
  }
  return null;
}
