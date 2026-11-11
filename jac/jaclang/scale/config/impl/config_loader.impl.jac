impl JacScaleConfig.get_plugin_name(self: JacScaleConfig) -> str {
    return "scale";
}

impl JacScaleConfig.get_config_schema(self: JacScaleConfig) -> dict[str, any] {
    return {"section": "scale", "options": scale_schema_options()};
}

impl JacScaleConfig.get_app_config_schema(self: JacScaleConfig) -> dict[str, any] {
    return {"section": "scale", "options": app_scale_schema()};
}

impl JacScaleConfig.get_config_strict_env(self: JacScaleConfig) -> str {
    return STRICT_ENV;
}

impl JacScaleConfig.get_default_config(self: JacScaleConfig) -> dict[str, any] {
    return {
        name: value
        for (name, value) in scale_defaults().items()
        if name not in SELF_DEFAULTED_SECTIONS
    };
}

impl _section_defaults(section: str) -> dict[str, any] {
    return scale_defaults()[section];
}

impl _scope_text(value: any) -> str {
    if isinstance(value, (list, tuple)) {
        return ' '.join(
            str(v).strip()
            for v in value
            if str(v).strip()
        );
    }
    return ' '.join(str(value or '').replace(',', ' ').split());
}

impl JacScaleConfig.get_sso_config(self: JacScaleConfig) -> dict[str, any] {
    sso_config = self.load()['sso'];
    resolved: dict[str, any] = {
        'host': sso_config['host'],
        'client_auth_callback_url': sso_config['client_auth_callback_url']
    };
    for platform in ('google', 'apple', 'github') {
        platform_config = sso_config[platform];
        resolved[platform] = {
            'client_id': platform_config['client_id'],
            'client_secret': platform_config['client_secret'],
            'scopes': _scope_text(platform_config['scopes'])
        };
    }
    resolved['firebase'] = {
        'project_id': resolve_firebase_project_id(
            FIREBASE_AUTH_PROJECT_ID_ENV, sso_config['firebase']['project_id'] or None
        )
            or ''
    };
    return resolved;
}

impl JacScaleConfig.get_deploy_database_config(self: JacScaleConfig) -> dict[str, any] {
    db_config = self.load()['database'];
    return {
        key: db_config[key]
        for key in ('url', 'deploy_mode', 'postgres_image', 'postgres_storage')
    };
}

impl JacScaleConfig.get_database_config(self: JacScaleConfig) -> dict[str, any] {
    resolved = self.get_deploy_database_config();
    resolved['url'] = os.environ.get('JAC_DB_URL') or resolved['url'];
    return resolved;
}


impl JacScaleConfig.get_kubernetes_config(self: JacScaleConfig) -> dict[str, any] {
    config = self.load();
    k8s_config = dict(config.get('kubernetes', {}));

    monitoring = self.get_monitoring_config();
    k8s_config['monitoring_enabled'] = monitoring['enabled'];
    k8s_config['k8s_metrics_enabled'] = monitoring['k8s_metrics_enabled'];
    k8s_config['prometheus_admin_password'] = monitoring['prometheus_admin_password'];

    k8s_config['admin_username'] = self.get_admin_config()['username'];

    system_deps = self.get_jac_config().get_plugin_deps("system");
    k8s_config['service_dependencies'] = [
        name
        for name in system_deps.keys()
        if name
    ];

    derived = k8s_safe_slug(self.get_jac_config().project.name, fallback='');
    if derived {
        k8s_config.setdefault('app_name', derived);
    }
    k8s_config_obj = KubernetesConfig.from_dict(KubernetesConfig, k8s_config);
    return k8s_config_obj.to_dict();
}

impl JacScaleConfig.get_server_config(self: JacScaleConfig) -> dict[str, any] {
    return {'structured_logs': bool(self.load()['server']['structured_logs'])};
}

impl JacScaleConfig.get_webhook_config(self: JacScaleConfig) -> dict[str, any] {
    webhook_config = self.load()['webhook'];
    return {
        'signature_header': webhook_config['signature_header'],
        'timestamp_header': webhook_config['timestamp_header'],
        'verify_signature': webhook_config['verify_signature'],
        'replay_tolerance_seconds': int(webhook_config['replay_tolerance_seconds']),
        'max_body_bytes': int(webhook_config['max_body_bytes']),
        'rate_limit_per_minute': int(webhook_config['rate_limit_per_minute']),
        'api_key_expiry_days': int(webhook_config['api_key_expiry_days']),
        'github_secret': str(webhook_config['github_secret'] or ''),
        'github_signature_header': str(
            webhook_config['github_signature_header']
                or _section_defaults('webhook')['github_signature_header']
        )
    };
}

impl JacScaleConfig.get_secrets_config(self: JacScaleConfig) -> dict[str, str] {
    return self.load()['secrets'];
}

impl sanitize_prometheus_namespace(name: str) -> str {
    import re;

    sanitized = re.sub(r'[^a-zA-Z0-9]', '_', name);

    sanitized = re.sub(r'_+', '_', sanitized);

    sanitized = sanitized.strip('_');

    if sanitized and sanitized[0].isdigit() {
        sanitized = f"_{sanitized}";
    }
    return sanitized or 'jaclang_scale';
}

impl _resolve_prometheus_namespace(configured: str | None, k8s_namespace: str) -> str {
    configured = "" if configured is None else str(configured);
    if not configured {
        return sanitize_prometheus_namespace(k8s_namespace);
    }
    sanitized = sanitize_prometheus_namespace(configured);
    if sanitized != configured and not _prometheus_namespace_warned {
        _prometheus_namespace_warned = True;
        import logging;
        logging.getLogger(__name__).warning(
            f"jac.toml [scale.monitoring] namespace '{configured}' is not a valid "
            f"Prometheus prefix; metrics are exported under '{sanitized}' instead. "
            "Update dashboards and alert rules that reference the old prefix."
        );
    }
    return sanitized;
}

impl JacScaleConfig.get_monitoring_config(self: JacScaleConfig) -> dict[str, any] {
    config = self.load();
    monitoring_config = config['monitoring'];
    k8s_config = config.get('kubernetes', {});
    namespace = _resolve_prometheus_namespace(
        monitoring_config['namespace'], k8s_config.get('namespace', 'default')
    );
    return {
        'enabled': monitoring_config['enabled'],
        'endpoint': monitoring_config['endpoint'],
        'namespace': namespace,
        'walker_metrics': monitoring_config['walker_metrics'],
        'histogram_buckets': monitoring_config['histogram_buckets'],
        'k8s_metrics_enabled': monitoring_config['k8s_metrics_enabled'],
        'prometheus_admin_password': monitoring_config['prometheus_admin_password']
    };
}

impl JacScaleConfig.get_events_config(self: JacScaleConfig) -> dict[str, any] {
    events_config = self.load()['events'];
    retry_config = events_config['retry'];
    return {
        'enabled': events_config['enabled'],
        'url': events_config['url'],
        'consumer_group': events_config['consumer_group'],
        'serializer': events_config['serializer'],
        'retry': {
            'max_attempts': retry_config['max_attempts'],
            'backoff_seconds': retry_config['backoff_seconds'],
            'dead_letter_suffix': retry_config['dead_letter_suffix']
        }
    };
}

impl _ws_positive(ws_config: dict[str, any], key: str) -> float {
    raw = ws_config[key];
    if isinstance(raw, bool) or not isinstance(raw, (int, float, str)) {
        raise ValueError(f"[scale.websocket].{key} must be a number, got {raw!r}.");
    }
    try {
        value = float(raw);
    } except ValueError {
        raise ValueError(f"[scale.websocket].{key} must be a number, got {raw!r}.");
    }
    if value <= 0 {
        raise ValueError(
            f"[scale.websocket].{key} must be greater than 0, got {raw!r}. "
            "These limits have no 'unlimited' value; set a high one instead."
        );
    }
    return value;
}

impl JacScaleConfig.get_websocket_config(self: JacScaleConfig) -> dict[str, any] {
    ws_config: dict[str, any] = self.load()['websocket'];
    backplane = ws_config['backplane'];
    if backplane is not None {
        backplane = str(backplane).lower();
    }
    return {
        'backplane': backplane,
        'max_message_bytes': int(_ws_positive(ws_config, 'max_message_bytes')),
        'max_connections_per_target': int(
            _ws_positive(ws_config, 'max_connections_per_target')
        ),
        'max_connections_per_user': int(
            _ws_positive(ws_config, 'max_connections_per_user')
        ),
        'max_anonymous_per_target': int(
            _ws_positive(ws_config, 'max_anonymous_per_target')
        ),
        'target_timeout_seconds': _ws_positive(ws_config, 'target_timeout_seconds'),
        'messages_per_second': _ws_positive(ws_config, 'messages_per_second')
    };
}

impl get_scale_config(project_dir: Path | None = None) -> JacScaleConfig {
    if _scale_config_instance is not None {
        cached_dir = _scale_config_instance.project_dir;
        if (
            project_dir is not None
            and cached_dir is not None
            and Path(project_dir).resolve() != cached_dir.resolve()
        ) {
            raise RuntimeError(
                f"get_scale_config(project_dir={project_dir}) called after the "
                f"config was already loaded for "
                f"{_scale_config_instance.project_dir}. Call "
                "reset_scale_config() first, or pass the config explicitly; "
                "returning the cached instance would silently read the wrong "
                "project's config."
            );
        }
        return _scale_config_instance;
    }
    new_instance = JacScaleConfig(project_dir);
    _scale_config_instance = new_instance;
    return new_instance;
}

impl peek_scale_config -> JacScaleConfig | None {
    return _scale_config_instance;
}

impl reset_scale_config -> None {
    _scale_config_instance = None;
    _prometheus_namespace_warned = False;
    _app_scale_cache.clear();
}

impl JacScaleConfig.get_telemetry_config(self: JacScaleConfig) -> dict[str, any] {
    return {'max_traces': int(self.load()['telemetry']['max_traces'])};
}

impl JacScaleConfig.get_scheduler_config(self: JacScaleConfig) -> dict[str, any] {
    scheduler_config = self.load()['scheduler'];
    defaults = _section_defaults('scheduler');
    floor: any = scheduler_min_interval(scheduler_config['min_interval']);
    cap: any = scheduler_job_cap(scheduler_config['max_jobs_per_user']);
    return {
        'collection': scheduler_config['collection'],
        'thread_pool_size': int(scheduler_config['thread_pool_size']),
        'misfire_grace_time': int(scheduler_config['misfire_grace_time']),
        'shutdown_timeout': int(scheduler_config['shutdown_timeout']),
        'system_user_password': scheduler_config['system_user_password'],
        'user_exists_ttl': float(scheduler_config['user_exists_ttl']),
        'min_interval': floor if floor is not None else defaults['min_interval'],
        'max_jobs_per_user': cap if cap is not None else defaults['max_jobs_per_user']
    };
}

impl JacScaleConfig.get_emailer_config(self: JacScaleConfig) -> dict[str, any] {
    emailer_config = self.load()['emailer'];
    smtp_config = dict(emailer_config['smtp']);
    smtp_password_env = os.environ.get('EMAILER_SMTP_PASSWORD');
    if smtp_password_env {
        smtp_config['password'] = smtp_password_env;
    }
    return {
        'provider': emailer_config['provider'],
        'enabled': bool(emailer_config['enabled']),
        'from_address': emailer_config['from_address'],
        'smtp': {
            'host': smtp_config['host'],
            'port': int(smtp_config['port']),
            'username': smtp_config['username'],
            'password': smtp_config['password'],
            'use_tls': bool(smtp_config['use_tls']),
            'timeout': float(smtp_config['timeout'])
        }
    };
}

impl JacScaleConfig.get_gateway_config(self: JacScaleConfig) -> dict[str, any] {
    config = self.load();
    return normalize_gateway_config(config.get('gateway', {}));
}

impl JacScaleConfig.get_app_scale_config(
    self: JacScaleConfig, app_name: str
) -> dict[str, any] {
    if not app_name {
        return {};
    }
    cached = _app_scale_cache.get(app_name);
    if cached is not None {
        return dict(cached);
    }
    try {
        resolved = app_scale_overrides(self.get_jac_config(), app_name);
    } except Exception {
        resolved = {};
    }
    _app_scale_cache[app_name] = resolved;
    return dict(resolved);
}


impl _pick_app_scale_keys(section: dict[str, any] | None) -> dict[str, any] {
    import copy;
    if not isinstance(section, dict) {
        return {};
    }
    return {
        key: copy.deepcopy(value)
        for (key, value) in section.items()
        if key in APP_SCALE_KEYS
    };
}


impl app_scale_overrides(config: any, app_name: str) -> dict[str, any] {
    if config is None or not app_name or app_name not in config.apps {
        return {};
    }
    app = config.apps[app_name];
    overlays = app.overlays if isinstance(app.overlays, dict) else {};
    declared = overlays.get("scale");
    if isinstance(declared, dict) {
        import from jaclang.project.config_schema { report_schema_findings }
        import from jaclang.scale.config.validation {
            STRICT_ENV,
            validate_app_scale_config
        }
        report_schema_findings(
            validate_app_scale_config(declared, app_name),
            f"apps.{app_name}.scale",
            STRICT_ENV
        );
    }
    try {
        effective = config.effective_for_app(app_name);
    } except Exception {
        return _pick_app_scale_keys(declared);
    }
    plugins = effective.plugins if isinstance(effective.plugins, dict) else {};
    return _pick_app_scale_keys(plugins.get("scale", {}));
}


impl normalize_gateway_config(gateway_config: dict[str, any] | None) -> dict[str, any] {
    defaults = _section_defaults('gateway');
    raw = dict(gateway_config or {});
    cors_defaults = defaults['cors'];
    cors_config = dict(raw.get('cors', {}) or {});
    cors: dict[str, any] = {
        'allow_origins': list(
            cors_config.get('allow_origins', cors_defaults['allow_origins'])
        ),
        'allow_methods': list(
            cors_config.get('allow_methods', cors_defaults['allow_methods'])
        ),
        'allow_headers': list(
            cors_config.get('allow_headers', cors_defaults['allow_headers'])
        ),
        'allow_credentials': bool(
            cors_config.get('allow_credentials', cors_defaults['allow_credentials'])
        ),
        'expose_headers': list(
            cors_config.get('expose_headers', cors_defaults['expose_headers'])
        ),
        'max_age': int(cors_config.get('max_age', cors_defaults['max_age']))
    };
    rl_defaults = defaults['rate_limit'];
    rl_config = dict(raw.get('rate_limit', {}) or {});
    identity_config = dict(raw.get('identity', {}) or {});
    normalized = {
        'colocate': bool(raw.get('colocate', defaults['colocate'])),
        'gateway_port': int(raw.get('gateway_port', defaults['gateway_port'])),
        'gateway_host': str(raw.get('gateway_host', defaults['gateway_host'])),
        'gateway_port_pinned': bool(raw.get('gateway_port_pinned', False)),
        'http_forward_timeout': float(
            raw.get('http_forward_timeout', defaults['http_forward_timeout'])
        ),
        'rate_limit': {
            'enabled': bool(rl_config.get('enabled', rl_defaults['enabled'])),
            'per_ip_rpm': int(rl_config.get('per_ip_rpm', rl_defaults['per_ip_rpm'])),
            'per_user_rpm': int(
                rl_config.get('per_user_rpm', rl_defaults['per_user_rpm'])
            ),
            'burst_multiplier': float(
                rl_config.get('burst_multiplier', rl_defaults['burst_multiplier'])
            ),
            'exempt_paths': list(
                rl_config.get('exempt_paths', rl_defaults['exempt_paths'])
            ),
            'shared': bool(rl_config.get('shared', rl_defaults['shared'])),
            'client_error_rpm': int(
                rl_config.get('client_error_rpm', rl_defaults['client_error_rpm'])
            )
        },
        'cors': cors,
        'identity': {
            'gateway_owned': bool(
                identity_config.get(
                    'gateway_owned', defaults['identity']['gateway_owned']
                )
            )
        },
        'ingress': dict(raw.get('ingress', {}) or {}),
        'shared_volumes': list(raw.get('shared_volumes', []) or []),
        'logs': dict(raw.get('logs', {}) or {}),
        'tracing': dict(raw.get('tracing', {}) or {})
    };
    cors_problem = cors_pair_problem(
        cors['allow_origins'],
        cors['allow_credentials'],
        '[scale.gateway.cors] allow_origins',
        '[scale.gateway.cors] allow_credentials'
    );
    if cors_problem {
        raise ValueError(cors_problem);
    }
    for boot_key in GATEWAY_BOOT_KEYS {
        if boot_key in raw and raw[boot_key] is not None {
            normalized[boot_key] = raw[boot_key];
        }
    }
    for pod_key in GATEWAY_POD_KEYS {
        if pod_key in raw and raw[pod_key] is not None {
            normalized[pod_key] = raw[pod_key];
        }
    }
    return normalized;
}

impl JacScaleConfig.get_admin_config(self: JacScaleConfig) -> dict[str, any] {
    admin_config = self.load()['admin'];
    return {
        'enabled': admin_config['enabled'],
        'username': admin_config['username'],
        'email': admin_config['email'],
        'default_password': str(
            os.environ.get(ADMIN_PASSWORD_ENV) or admin_config['default_password'] or ''
        ),
        'session_expiry_hours': int(admin_config['session_expiry_hours']),
        'require_password_reset': admin_config['require_password_reset']
    };
}
