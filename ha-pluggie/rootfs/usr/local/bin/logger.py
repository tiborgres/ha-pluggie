#!/usr/local/bin/python
"""
Logger module for Pluggie Python scripts.
Provides consistent logging functionality with colored output
similar to Bashio scripts.
"""

import os
import sys
import json
import logging
from enum import Enum


class LogColor:
    """ANSI color codes for log messages"""
    RESET = "\033[0m"
    DEFAULT = "\033[39m"
    BLACK = "\033[30m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    LIGHT_GRAY = "\033[37m"


class LogLevel(Enum):
    """Log levels matching Bashio log levels"""
    ALL = 8
    TRACE = 7
    DEBUG = 6
    INFO = 5
    NOTICE = 4
    WARNING = 3
    ERROR = 2
    FATAL = 1
    CRITICAL = 1
    OFF = 0


# Mapping from Bashio log levels to Python logging levels
BASHIO_TO_PYTHON_LOG_LEVELS = {
    'all': logging.DEBUG,
    'trace': logging.DEBUG,
    'debug': logging.DEBUG,
    'info': logging.INFO,
    'notice': logging.INFO,
    'warning': logging.WARNING,
    'error': logging.ERROR,
    'fatal': logging.CRITICAL,
    'critical': logging.CRITICAL,
    'off': logging.CRITICAL + 10
}

# Mapping from log level to color
LOG_LEVEL_COLORS = {
    logging.DEBUG: LogColor.BLUE,
    logging.INFO: LogColor.GREEN,
    logging.WARNING: LogColor.YELLOW,
    logging.ERROR: LogColor.RED,
    logging.CRITICAL: LogColor.RED,
}


class ColoredFormatter(logging.Formatter):
    """Custom formatter that adds colors to log messages based on level"""

    def format(self, record):
        # Save original message
        original_message = record.msg

        # Add color to message based on log level
        color = LOG_LEVEL_COLORS.get(record.levelno, LogColor.DEFAULT)
        record.msg = f"{color}{original_message}{LogColor.RESET}"

        # Format the message with parent formatter
        result = super().format(record)

        # Restore original message for future formatting
        record.msg = original_message

        return result


def setup_logging(name=None, log_level=None):
    """
    Configure logging with colored output, similar to Bashio.

    Args:
        name: Logger name (optional, uses root logger if None)
        log_level: Log level (optional, uses environment LOG_LEVEL if None)

    Returns:
        configured logger instance
    """
    # Get logger (root logger if name is None)
    logger = logging.getLogger(name)

    # Remove any existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    # Get log level from environment if not specified
    if log_level is None:
        bashio_log_level = os.environ.get('LOG_LEVEL', 'info').lower()
        log_level = BASHIO_TO_PYTHON_LOG_LEVELS.get(bashio_log_level, logging.INFO)

    # Configure logging to stdout with colored formatter
    handler = logging.StreamHandler(sys.stdout)
    formatter = ColoredFormatter('[%(asctime)s] %(levelname)s: %(message)s', '%H:%M:%S')
    handler.setFormatter(formatter)

    # Set log level and add handler
    logger.setLevel(log_level)
    logger.addHandler(handler)

    # Return configured logger
    return logger


def get_logger(name=None):
    """
    Get a pre-configured logger with colored output.
    If logger already exists, returns it, otherwise creates a new one.

    Args:
        name: Logger name (optional)

    Returns:
        logger instance with colored output
    """
    logger = logging.getLogger(name)

    # If logger doesn't have handlers, set it up
    if not logger.handlers:
        return setup_logging(name)

    return logger


def reload_options_log_level(options_file="/data/pluggie.json"):
    try:
        log_level = "info"
        if os.path.exists(options_file):
            try:
                with open(options_file, 'r') as f:
                    file_content = f.read()
                    options = json.loads(file_content)
                    
                    if 'log_level' in options:
                        log_level = options['log_level'].lower()

            except Exception as read_error:
                logging.error(f"Error reading options file: {read_error}")
                return None
        else:
            logging.warning(f"Options file {options_file} does not exist")

        python_log_level = BASHIO_TO_PYTHON_LOG_LEVELS.get(log_level, logging.INFO)

        # Update root logger level
        root_logger = logging.getLogger()
        current_level = root_logger.getEffectiveLevel()
        
        root_logger.setLevel(python_log_level)
        new_level = root_logger.getEffectiveLevel()

        return python_log_level
    except Exception as e:
        logging.error(f"Error reloading log level: {e}")
        return None
