impl SessionContext.merge_alerts {
    if self.target is self.caller or self.target.internal {
        return;
    }
    self.caller.errors_had.extend(self.target.errors_had[self.errors_mark:]);
    self.caller.warnings_had.extend(self.target.warnings_had[self.warnings_mark:]);
}

impl select_context(
    file_path: str, program: JacProgram, options: CompileOptions
) -> SessionContext {
    target = program;
    if not program.internal {
        options = bind_options(file_path, program, options);
        if not active_host().native_session_active(program) {
            target = context_program(program, options);
        }
    }
    return SessionContext(
        caller=program,
        target=target,
        options=options,
        errors_mark=len(target.errors_had),
        warnings_mark=len(target.warnings_had)
    );
}

impl annex_parent(
    file_path: str, program: JacProgram, use_str: (str | None), options: CompileOptions
) -> (str | None) {
    if use_str is not None or not options.resolve_annex_parent {
        return None;
    }
    host = active_host();
    if not host.path_facts(file_path).is_annex {
        return None;
    }
    base_path = host.base_file(file_path);
    if base_path and base_path not in program.mod.hub {
        return base_path;
    }
    return None;
}

impl inherit_session_options(
    program: JacProgram, options: CompileOptions, closure: (CompileOptions | None)
) -> CompileOptions {
    previous = program.options;
    if previous is not None
        and not (options.nogc_enforce_all or options.memory_enforce) {
        options.nogc_enforce_all = previous.nogc_enforce_all;
        options.memory_enforce = previous.memory_enforce;
        options.memory_exempt = previous.memory_exempt;
    }
    if previous is not None and not options.default_codespace {
        options.default_codespace = previous.default_codespace;
    }
    if closure is not None and closure is not options and closure.need_full_ast {
        options.need_full_ast = True;
    }
    if closure is not None and closure is not options and closure.native_tree_demand {
        options.native_tree_demand = True;
    }
    program.options = options;
    if options.default_codespace {
        import from jaclang.compiler.frontend.codeinfo {
            set_effective_default_codespace
        }
        set_effective_default_codespace(options.default_codespace);
    }
    return options;
}

impl drop_native_bindings(mod: uni.Module, resolved: str) {
    key = os.path.realpath(resolved);
    manifest = mod.gen.interop_manifest;
    if not isinstance(manifest, InteropManifest) or not manifest.bindings {
        return;
    }
    stale = [
        name
        for (name, b) in manifest.bindings.items()
        if (
            b.source_context == InteropContext.NATIVE
            and b.source_module
            and os.path.realpath(b.source_module) == key
        )
    ];
    for name in stale {
        manifest.bindings.pop(name, None);
    }
}
