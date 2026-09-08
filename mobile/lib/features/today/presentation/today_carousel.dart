import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthy/core/theme/app_colors.dart';

class TodayCarousel extends StatefulWidget {
  const TodayCarousel({super.key});

  @override
  State<TodayCarousel> createState() => _TodayCarouselState();
}

class _TodayCarouselState extends State<TodayCarousel> {
  static const _slides = [
    (
      image: 'assets/today/healthy-meal-1.png',
      title: '把均衡饮食放进每一天',
      subtitle: '从真实目标出发，轻松安排今天',
    ),
    (
      image: 'assets/today/healthy-meal-2.png',
      title: '认真吃饭，也能轻盈生活',
      subtitle: '规律的一餐，比仓促的节食更可靠',
    ),
    (
      image: 'assets/today/healthy-meal-3.png',
      title: '给身体留一点从容',
      subtitle: '饮食、运动与睡眠，一步一步来',
    ),
  ];

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion && _timer != null) return;
    _reduceMotion = reduceMotion;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_reduceMotion) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_controller.hasClients) return;
      _controller.animateToPage(
        (_page + 1) % _slides.length,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 190,
          child: Semantics(
            label: '健康餐食轮播，第 ${_page + 1} 张，共 ${_slides.length} 张',
            container: true,
            child: PageView.builder(
              controller: _controller,
              itemCount: _slides.length,
              onPageChanged: (page) {
                setState(() => _page = page);
                _restartTimer();
              },
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      slide.image,
                      fit: BoxFit.cover,
                      semanticLabel: '健康餐食照片',
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC10271E)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slide.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            slide.subtitle,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          _slides.length,
          (index) => Container(
            key: Key('today-carousel-indicator-$index'),
            width: index == _page ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: index == _page ? AppColors.green : AppColors.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    ],
  );
}
