impl UtilityFactory.create_metrics(
    metrics_type: str = 'prometheus',
    config: (dict[str, any] | None) = None,
    worker_count: int = 1
) -> MetricsCollector {
    if not config or not config.get('enabled', False) {
        return NoOpMetricsCollector();
    }

    if metrics_type == 'prometheus' {
        if not is_optional_available("prometheus_client") {
            return NoOpMetricsCollector();
        }
        import from jaclang.scale.observability.prometheus_metrics {
            PrometheusMetricsCollector
        }
        return PrometheusMetricsCollector(config=config, worker_count=worker_count);
    } elif metrics_type == 'none' {
        return NoOpMetricsCollector();
    } else {
        raise ValueError(f"Unsupported metrics type: {metrics_type}");
    }
}
