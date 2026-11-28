import 'package:flutter_test/flutter_test.dart';
import 'package:paigham/widgets/media_views.dart';
void main() {
  test('album layouts fill width', () {
    for (final rs in [[1.5,1.5],[0.7,1.3],[0.6,1.4,1.0],[1.5,1.0,0.8],[1.0,1.0,1.0,1.0],[1.3,0.7,1.0,1.6,0.8],[for (var i=0;i<10;i++) 1.0 + (i%3)*0.3]]) {
      final r = albumLayout(rs, 300);
      expect(r.length, rs.length);
      final right = r.map((e) => e.right).reduce((a,b)=>a>b?a:b);
      expect(right, closeTo(300, 0.01));
    }
  });
}
