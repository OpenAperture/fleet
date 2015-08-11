# OpenAperture.Fleet

[![Build Status](https://semaphoreci.com/api/v1/projects/3287e3d0-2883-40a8-b97c-083e6bc69eb6/508998/badge.svg)](https://semaphoreci.com/perceptive/fleet)

This reusable Elixir messaging library contains several modules for working with Fleet and CoreOS.  It provides the following features:

* Provides a Parser for Fleet service files (converts to the appropriate Map)
* Provides a Systemd wrapper for executing systemd calls
* Provides an Etcd wrapper for executing Etcd calls
* Provides a cache for storing Etcd instances

## Module Configuration

The following configuration values must be defined as part of your application's environment configuration files:

* Temporary Directory
	* Type:  String
	* Description:  The locatino of the temporary directory for writing files
  * Environment Configuration (.exs): :openaperture_fleet, :tmpdir  

## Building & Testing

The normal elixir project setup steps are required:

```iex
mix do deps.get, deps.compile
```

You can then run the tests

```iex
MIX_ENV=test mix test test/
```
