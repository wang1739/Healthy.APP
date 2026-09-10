import 'package:flutter/material.dart';
import 'package:healthy/core/api/api_client.dart';
import 'package:healthy/features/report/domain/report_data.dart';

class ReportSourcesPage extends StatelessWidget {
  const ReportSourcesPage({
    required this.api,
    required this.reportId,
    required this.section,
    required this.onOpenSource,
    this.metric,
    super.key,
  });
  final ApiClient api;
  final String reportId;
  final String section;
  final String? metric;
  final ValueChanged<ReportSource> onOpenSource;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('统计依据')),
    body: SafeArea(
      child: FutureBuilder<List<ReportSource>>(
        future: api.getReportSources(
          reportId,
          section: section,
          metric: metric,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(ApiClient.errorMessage(snapshot.error!)));
          }
          final values = snapshot.data ?? const [];
          if (values.isEmpty) return const Center(child: Text('暂无可展示的原始依据'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: values
                .map(
                  (v) => Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListTile(
                      title: Text(v.displayLabel),
                      subtitle: Text(
                        '${v.localDate.year}年${v.localDate.month}月${v.localDate.day}日',
                      ),
                      trailing: v.available
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: v.available ? () => onOpenSource(v) : null,
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ),
  );
}
