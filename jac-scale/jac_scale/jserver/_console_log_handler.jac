"""Custom logging handler for jac-scale console output.

This module is separate so it can be referenced by import path in log_config,
making it picklable for multi-worker mode.
"""

import logging;

"""A logging handler that forwards log messages to jac-super's console."""
class ConsoleLogHandler(logging.Handler) {
    def emit(self: ConsoleLogHandler, record: logging.LogRecord) -> None {
        import from jaclang.cli.console { console }
        message = self.format(record);
        console.print(f"  {message}");
    }
}
