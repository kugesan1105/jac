impl AutoscalerFactory.create(
    engine: (str | None), config: dict[str, any], logger: (Logger | None) = None
) -> Autoscaler {
    if engine is None or engine == "hpa" {
        import from jaclang.scale.deploy.autoscale.hpa_autoscaler { HPAAutoscaler }
        return HPAAutoscaler(logger=logger);
    }
    if engine == "keda" {
        import from jaclang.scale.deploy.autoscale.keda_autoscaler { KEDAAutoscaler }
        import from jaclang.scale.runtime.context.service_routing {
            resolve_interceptor_service_address
        }
        return KEDAAutoscaler(
            logger=logger,
            interceptor_service_address=resolve_interceptor_service_address(config)
        );
    }
    raise ValueError(
        f"Unsupported autoscaler engine: '{engine}'. Supported engines: 'hpa', 'keda'."
    );
}
