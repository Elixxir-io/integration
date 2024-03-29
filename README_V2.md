# Integration V2 (post-cleanup)

The integration test has been split into components and refactored to make this
repository both easier to use and more modular. It retains all the old
functionality with some helpful additions.

## Repository Structure

``` text
integration/
├── run.sh      # Basic integration runner
├── start.sh    # More advanced runner for continuous/simultaneous testing
├── stop.sh     # Cleanup for start.sh
├── tests/      # Tests directory contains individual tests which can be run by the top-level scripts
│   ├── basice2e_local # Test names correspond to the directory name
│   │   ├── run.sh     # Each test must contain a run.sh script and clients.goldoutput directory
│   │   └── clients.goldoutput/
│   ├── channels
│   └── ...
├── network/       # This network package is used across all tests
│   ├── network.sh # network and/or cleanup files should be sourced into files as always
│   ├── cleanup.sh
│   └── [network configs]
└── results/       # This is generated by running tests and is not in source control
    ├── network    # Local network outputs to results/network
    ├── basice2e_local
    │   ├── clients/          # Raw client outputs for this test
    │   ├── clients-cleaned/  # Cleaned client outputs for this test
    │   └── testout.txt       # Raw console output for this test
    ├── ...                   # Results contain directories of client logs for each test run
    └── testreport.txt
```

## Running Integration Tests

Integration tests can be run as they always have been, with some small changes.

All testing must now run through `run.sh` in the root directory. By default,
the script will run all tests in sequence. it accepts an optional argument for
the environment (`mainnet`, `devnet`, `protonet`).

```shell
./run.sh [mainnet|devnet|protonet]
```

It supports an additional named argument for running single tests or subsets as
well.

```shell
./run.sh --run [testname]
```

Use `run.sh help` for more information on the usage.

## Advanced Integration Testing

Also included in the repo are the scripts `start.sh` and `stop.sh`. These can
be used to the same effect as the single runner, with some notable differences.

Running `start.sh` will check for a live network in the expected location, and
will connect to it if found. This is somewhat intelligent, but not well tested yet.
It will not shut down the network when the test is finished, leaving it active
for other local testing if needed. To shut down the network, use the `stop.sh`
script. The help commands on each script contain more detailed information on
usage.

## Adding New Tests

The `generatePackage.py` script has been deprecated by this update. While it may
be updated in the future, adding new tests is not nearly as complicated anymore.

A template for `run.sh` can be found in `gen/`. To create a new test, add a directory
to `tests/` with the desired test name. Copy the `run.sh` file from `gen/`, and
add a `clients.goldoutput/` directory to your new test package. You can now
add test code to `tests/{your_test_name}/run.sh`, and run it using the `--run`
argument with `run.sh` in the root directory.

New tests must be separately added to the list in `run.sh` to be run as part of
the full suite. Additionally, a new step must be added to the `.gitlab_ci` file
for it to run as part of continuous integration. An example of this can be found
below:

```yaml
your_test_name:
  stage: tests
  image: $DOCKER_IMAGE
  script:
    - mkdir -p ~/.elixxir
    - echo $PWD
    - rm -fr results
    - ./run.sh --run { your_test_name_here }
  artifacts:
    when: always
    expire_in: '1 day'
    paths:
      - results/
      - bin/
```

## Planned Upgrades

Leaving this section as a note for the future, some things that are out of scope
for the time being but would improve the quality of this repo.

- Finish splitting up basice2e
- bring back generatePackage.py?  (may not be needed, this is fairly easy now)
- CI testing using single network
- Suppress individual test output since this now goes to a file, add verbose flag for users who want the old behavior
- Top-level script code review
    - Potential rewrite/wrapper in python?

