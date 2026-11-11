import copy;

def _http_activation_nested_schema(cluster_scoped: bool = False) -> dict[str, any];


def app_scale_schema -> dict[str, any];


def schema_defaults(options: dict[str, any]) -> dict[str, any];


def scale_defaults -> dict[str, any];


class JacScalePluginConfig {
    static def get_plugin_metadata -> dict[str, any];
    static def get_config_schema -> dict[str, any];
}
