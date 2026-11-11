class AutoscalerFactory {
    static def create(
        engine: (str | None), config: dict[str, any], logger: (Logger | None) = None
    ) -> Autoscaler;
}
