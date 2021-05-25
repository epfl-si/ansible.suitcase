# Changes in version 1.0.0

- Attempt to re-use the system-provided python3
  - Tolerate a plurality of Python versions i.e. `$SUITCASE_PYTHON_VERSION` becomes `$SUITCASE_PYTHON_VERSIONS`
- New variable SUITCASE_NO_EYAML to short-circuit ruby et al

When using both features simultaneously, a successful `ansible-deps-cache` directory shrinks down to ~300 megabytes on Mac OS X.
