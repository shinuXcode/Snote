import 'dart:ui';
import 'pen_config.dart';
import 'stroke.dart';

class StrokeCodec {
  static Map<String,Object?> strokeToJson(Stroke s)=>{'id':s.id,'pen':{'type':s.pen.type.name,'color':s.pen.color.value,'size':s.pen.size,'opacity':s.pen.opacity},'points':s.points.map((p)=>{'x':p.position.dx,'y':p.position.dy,'pressure':p.pressure,'timestamp':p.timestamp}).toList()};
  static Map<String,Object?> strokesToDocument(List<Stroke> strokes)=>{'version':1,'strokes':strokes.map(strokeToJson).toList()};
  static Color colorFromInt(Object? value)=>Color((value as num?)?.toInt()??0xff000000);
}
