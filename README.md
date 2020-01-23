# Bosco Override Template

## What is this?

This is a configuration template for the SLATE [OSG HostedCE](https://portal.slateci.io/applications/incubator/osg-hosted-ce) application. This application functions as an entrypoint for batch jobs entering a local cluster from the [Open Science Grid](https://opensciencegrid.org/).

Bosco is a component of the CE responsible for managing job submission to the computer cluster(s). Some attributes of bosco may need to be overridden/patched in order to get a functional CE at certain sites. This is because Bosco is not always able to determine environment specific details on the remote clusters.

A common example is the binary path for the batch system's executables. Bosco expects to find the executables in `/usr/bin`, but the remote batch system may have binaries come from somewhere else. This option can be overriden in `bosco_override/glite/etc/blah.config`

## How to use

TODO
