import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平台视图纹理绘制原点必须对齐到整数物理像素（消除分数 DPI 半像素 `GL_NEAREST` 锯齿/糊字）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('physicalPixelSnapOffset', () {
    test('整数物理坐标返回零偏移', () {
      for (final (double x, double y, double dpr) in <(double, double, double)>[
        (0.0, 0.0, 1.5),
        (22.0, 54.0, 1.5),
        (-10.0, -20.0, 1.5),
        (10.0, 15.5, 2.0),
        (12.0, 16.0, 1.25),
      ]) {
        expect(
          physicalPixelSnapOffset(
            transform: Matrix4.translationValues(x, y, 0.0),
            devicePixelRatio: dpr,
          ),
          Offset.zero,
        );
      }
    });

    test('半像素边界 k + 0.5 向下对齐到 k（保持 top-left 覆盖无边缘漏底）', () {
      final List<
        ({double x, double y, double dpr, double targetX, double targetY})
      >
      cases =
          <({double x, double y, double dpr, double targetX, double targetY})>[
            (
              x: 21.333333333333332 + 1.0,
              y: 53.666666666666664,
              dpr: 1.5,
              targetX: 33.0,
              targetY: 80.0,
            ),
            (x: 23.0, y: 1.0, dpr: 1.5, targetX: 34.0, targetY: 1.0),
            (x: 10.0, y: 14.0, dpr: 1.25, targetX: 12.0, targetY: 17.0),
            (x: 10.0, y: 2.0, dpr: 1.75, targetX: 17.0, targetY: 3.0),
            (x: 10.25, y: 20.25, dpr: 2.0, targetX: 20.0, targetY: 40.0),
            (x: -7.0, y: -1.0, dpr: 1.5, targetX: -11.0, targetY: -2.0),
          ];
      for (final c in cases) {
        final Offset delta = physicalPixelSnapOffset(
          transform: Matrix4.translationValues(c.x, c.y, 0.0),
          devicePixelRatio: c.dpr,
        );
        final double snappedX = (c.x + delta.dx) * c.dpr;
        final double snappedY = (c.y + delta.dy) * c.dpr;
        expect(snappedX, closeTo(c.targetX, 1e-6));
        expect(snappedY, closeTo(c.targetY, 1e-6));
        expect((delta.dx * c.dpr).abs(), lessThanOrEqualTo(0.5 + 1e-6));
        expect((delta.dy * c.dpr).abs(), lessThanOrEqualTo(0.5 + 1e-6));
      }
    });

    test('跨 .5 浮点微扰稳定对齐到同一整数物理像素', () {
      const double dpr = 1.5;
      for (final double physX in <double>[33.5 + 1e-12, 33.5 - 1e-12]) {
        final double logicalX = physX / dpr;
        final Offset delta = physicalPixelSnapOffset(
          transform: Matrix4.translationValues(logicalX, 80.5 / dpr, 0.0),
          devicePixelRatio: dpr,
        );
        expect((logicalX + delta.dx) * dpr, closeTo(33.0, 1e-6));
        expect((80.5 / dpr + delta.dy) * dpr, closeTo(80.0, 1e-6));
      }
    });

    test('任意小数物理坐标就近对齐到整数且偏移不超过 0.5 物理像素', () {
      const double dpr = 1.5;
      final List<(double phys, double expected)> samples = <(double, double)>[
        (33.25, 33.0),
        (33.6, 34.0),
        (33.75, 34.0),
        (-10.4, -10.0),
        (-10.6, -11.0),
      ];
      for (final (double phys, double expected) in samples) {
        final double logical = phys / dpr;
        final Offset delta = physicalPixelSnapOffset(
          transform: Matrix4.translationValues(logical, logical, 0.0),
          devicePixelRatio: dpr,
        );
        expect((logical + delta.dx) * dpr, closeTo(expected, 1e-6));
        expect((logical + delta.dy) * dpr, closeTo(expected, 1e-6));
        expect((delta.dx * dpr).abs(), lessThanOrEqualTo(0.5 + 1e-6));
      }
    });

    test('带祖先等比或非等比缩放时折算回本地逻辑偏移后仍精确对齐', () {
      const double dpr = 1.5;
      final Matrix4 scaled = Matrix4.translationValues(25.0, 37.5, 0.0)
        ..scaleByDouble(1.16, 1.16, 1.0, 1.0);
      final Offset delta = physicalPixelSnapOffset(
        transform: scaled,
        devicePixelRatio: dpr,
      );
      expect((25.0 + 1.16 * delta.dx) * dpr, closeTo(37.0, 1e-6));
      expect((37.5 + 1.16 * delta.dy) * dpr, closeTo(56.0, 1e-6));

      final Matrix4 nonUniform = Matrix4.translationValues(
        22.333333333333332,
        53.666666666666664,
        0.0,
      )..scaleByDouble(1.2, 0.9, 1.0, 1.0);
      final Offset nonUniformDelta = physicalPixelSnapOffset(
        transform: nonUniform,
        devicePixelRatio: dpr,
      );
      expect(
        (22.333333333333332 + 1.2 * nonUniformDelta.dx) * dpr,
        closeTo(33.0, 1e-6),
      );
      expect(
        (53.666666666666664 + 0.9 * nonUniformDelta.dy) * dpr,
        closeTo(80.0, 1e-6),
      );
    });

    test('旋转、错切、透视或退化变换返回 Offset.zero', () {
      expect(
        physicalPixelSnapOffset(
          transform: Matrix4.rotationZ(0.2)
            ..setTranslationRaw(22.3333333, 53.6666666, 0.0),
          devicePixelRatio: 1.5,
        ),
        Offset.zero,
      );
      final Matrix4 shear = Matrix4.identity()..setEntry(0, 1, 0.2);
      shear.setTranslationRaw(22.3333333, 53.6666666, 0.0);
      expect(
        physicalPixelSnapOffset(transform: shear, devicePixelRatio: 1.5),
        Offset.zero,
      );
      final Matrix4 perspective = Matrix4.identity()..setEntry(3, 0, 0.001);
      expect(
        physicalPixelSnapOffset(transform: perspective, devicePixelRatio: 1.5),
        Offset.zero,
      );
      expect(
        physicalPixelSnapOffset(
          transform: Matrix4.diagonal3Values(0.0, 1.0, 1.0),
          devicePixelRatio: 1.5,
        ),
        Offset.zero,
      );
      expect(
        physicalPixelSnapOffset(
          transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
          devicePixelRatio: 1.5,
        ),
        Offset.zero,
      );
      expect(
        physicalPixelSnapOffset(
          transform: Matrix4.translationValues(double.nan, 10.0, 0.0),
          devicePixelRatio: 1.5,
        ),
        Offset.zero,
      );
      expect(
        physicalPixelSnapOffset(
          transform: Matrix4.translationValues(22.3333333, 53.6666666, 0.0),
          devicePixelRatio: 0.0,
        ),
        Offset.zero,
      );
    });
  });

  group('CustomPlatformView 物理像素原点对齐', () {
    const MethodChannel manager = MethodChannel(
      'com.pichillilorenzo/flutter_inappwebview_manager',
    );
    const MethodChannel view = MethodChannel(
      'com.pichillilorenzo/custom_platform_view_7',
    );
    const MethodChannel events = MethodChannel(
      'com.pichillilorenzo/custom_platform_view_7_events',
    );

    setUp(() {
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(manager, (MethodCall call) async {
        if (call.method == 'createInAppWebView') return 7;
        return null;
      });
      messenger.setMockMethodCallHandler(view, (MethodCall call) async {
        return null;
      });
      messenger.setMockMethodCallHandler(events, (MethodCall call) async {
        return null;
      });
    });

    tearDown(() {
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final MethodChannel c in <MethodChannel>[manager, view, events]) {
        messenger.setMockMethodCallHandler(c, null);
      }
    });

    Offset? findTexturePhysicalOrigin(Layer layer, Matrix4 current) {
      final Matrix4 next = current.clone();
      if (layer is TransformLayer) {
        if (layer.offset != Offset.zero) {
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0.0),
          );
        }
        if (layer.transform != null) {
          next.multiply(layer.transform!);
        }
      } else if (layer is OffsetLayer) {
        if (layer.offset != Offset.zero) {
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0.0),
          );
        }
      }
      if (layer is TextureLayer) {
        return MatrixUtils.transformPoint(next, layer.rect.topLeft);
      }
      if (layer is ContainerLayer) {
        Layer? child = layer.firstChild;
        while (child != null) {
          final Offset? found = findTexturePhysicalOrigin(child, next);
          if (found != null) return found;
          child = child.nextSibling;
        }
      }
      return null;
    }

    Offset texturePhysicalOrigin(WidgetTester tester) {
      final Layer? rootLayer = tester.binding.renderViews.first.debugLayer;
      expect(rootLayer, isNotNull);
      final Offset? origin = findTexturePhysicalOrigin(
        rootLayer!,
        Matrix4.identity(),
      );
      expect(
        origin,
        isNotNull,
        reason: 'rendered layer tree should contain a TextureLayer',
      );
      return origin!;
    }

    testWidgets('150% DPI 半像素原点 (33.5, 80.5) 对齐到 (33.0, 80.0)', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 22.333333333333332,
                top: 53.666666666666664,
                width: 478,
                height: 436,
                child: CustomPlatformView(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(ClipRect), findsOneWidget);
      expect(find.byType(OverflowBox), findsOneWidget);
      final Offset origin = texturePhysicalOrigin(tester);
      expect(origin.dx, closeTo(33.0, 1e-4));
      expect(origin.dy, closeTo(80.0, 1e-4));
    });

    testWidgets('祖先 RepaintBoundary 仅平移至半像素边界时仍能跟随重新对齐', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);

      const Key boundaryKey = Key('popup-boundary');
      Widget buildScene({required double left, required double top}) =>
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: left,
                  top: top,
                  width: 200,
                  height: 150,
                  child: const RepaintBoundary(
                    key: boundaryKey,
                    child: CustomPlatformView(),
                  ),
                ),
              ],
            ),
          );

      await tester.pumpWidget(buildScene(left: 22.0, top: 54.0));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final Offset initial = texturePhysicalOrigin(tester);
      expect(initial.dx, closeTo(33.0, 1e-4));
      expect(initial.dy, closeTo(81.0, 1e-4));

      await tester.pumpWidget(buildScene(left: 23.0, top: 53.666666666666664));
      await tester.pump();
      await tester.pump();

      final Offset moved = texturePhysicalOrigin(tester);
      expect(moved.dx, closeTo(34.0, 1e-4));
      expect(moved.dy, closeTo(80.0, 1e-4));
    });

    testWidgets('祖先存在 Transform.scale 时纹理物理原点仍对齐整数', (
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.0, top: 15.0),
              child: Transform.scale(
                scale: 1.16,
                alignment: Alignment.topLeft,
                child: const SizedBox(
                  width: 300,
                  height: 200,
                  child: CustomPlatformView(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final Offset origin = texturePhysicalOrigin(tester);
      expect(origin.dx, closeTo(origin.dx.roundToDouble(), 1e-4));
      expect(origin.dy, closeTo(origin.dy.roundToDouble(), 1e-4));
    });

    testWidgets('125% 与 175% DPI 半像素边界同样对齐整数物理像素', (WidgetTester tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);

      tester.view.devicePixelRatio = 1.25;
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 10.0,
                top: 10.0,
                width: 240,
                height: 160,
                child: CustomPlatformView(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final Offset origin125 = texturePhysicalOrigin(tester);
      expect(origin125.dx, closeTo(12.0, 1e-4));
      expect(origin125.dy, closeTo(12.0, 1e-4));

      tester.view.devicePixelRatio = 1.75;
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: <Widget>[
              Positioned(
                key: Key('dpr-175'),
                left: 10.0,
                top: 10.0,
                width: 240,
                height: 160,
                child: CustomPlatformView(),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final Offset origin175 = texturePhysicalOrigin(tester);
      expect(origin175.dx, closeTo(17.0, 1e-4));
      expect(origin175.dy, closeTo(17.0, 1e-4));
    });
  });
}
