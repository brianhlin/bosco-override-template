# Bosco Override Template

## What is this?

This is a configuration template for the SLATE [OSG HostedCE](https://portal.slateci.io/applications/incubator/osg-hosted-ce) application. This application functions as an entrypoint for batch jobs entering a local cluster from the [Open Science Grid](https://opensciencegrid.org/).

Bosco is a component of the CE responsible for managing job submission to the computer cluster(s). Some attributes of bosco may need to be overridden/patched in order to get a functional CE at certain sites. This is because Bosco is not always able to determine environment specific details on the remote clusters.

A common example is the binary path for the batch system's executables. Bosco expects to find the executables in `/usr/bin`, but the remote batch system may have binaries come from somewhere else. This option can be overriden in `bosco_override/glite/etc/blah.config`

Batch system specific parameters can be added in the scripts found in `bosco_override/glite/etc/blahp/`

## How to use

When preparing the configuration for a new SLATE OSG HostedCE you will need to setup a **git repository** which the application will use to clone the overrides to the remote cluster. 

Simply **fork** this repository to a suitable location.

Rename your respository to whatever works best for you. I have named mine `utah-bosco`.

Change the `RESOURCE_NAME` directory to match name of your resource. This is specified in the SLATE application config (also called `values.yaml`)

```
Site:
  Resource: SLATE_US_UUTAH_LONEPEAK
  ResourceGroup: CHPC Group
```

In my case I would name this  directory `SLATE_US_UUTAH_LONEPEAK`

After this you can change the files you need to override.

Files that are not overridden can be removed from the repository for simplicity.

You are now ready to point your CE application config at your forked repoository.

```
# Options to allow override of the bosco directory from arbitrary git repos
# Bosco override dirs are expected in the following location in the git repo:
#   <RESOURCE NAME>/bosco_override/
BoscoOverrides:
  Enabled: false
  GitEndpoint: "https://github.com/slateci/utah-bosco.git"
  RepoNeedsPrivKey: false
  GitKeySecret: none
```

It is also possible to store these values in a private repository configured with a private key stored as a [SLATE Secret](https://slateci.io/docs/tools/).

This repository can also be used as an example for what can be overriden to fix issues for an existing CE.
