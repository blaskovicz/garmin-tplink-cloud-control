# garmin-tplink-cloud-control [![Build Status](https://travis-ci.org/blaskovicz/garmin-tplink-cloud-control.svg?branch=master)](https://travis-ci.org/blaskovicz/garmin-tplink-cloud-control)
>Control and visualize the state of your TPLink Cloud / Kasa devices from your Garmin Wearable.

## Features
* View the state of all TPLink devices in an owned household (online, offline, powered on, powered off)

* Toggle the power state of each connected device.

* Oauth2 authentication

## Screenshots
![summary view](https://i.imgur.com/Y3txYdm.png)
![list view](https://i.imgur.com/06RGyTD.png)

## Development

* _Docker_: this will run a build similar to how TravisCI will execute it (for build debugging). Simply run `docker build .` in the root directory of this git repo.
* _Scripts_: run the [`install-connectiq-sdk.sh`](install-connectiq-sdk.sh) and [`build-connectiq-app.sh`](build-connectiq-app.sh)
scripts manually after creating a `./source/Env.mc` file from `./source/Env.mc.sample`. This is similar to the previous step, but avoids the overhead of docker.
* _Eclipse_: It's recommended to follow Garmin's [getting started](https://developer.garmin.com/connect-iq/programmers-guide/getting-started/) guide for setting
this project up and running in Eclipse. Before it can build, the project will need a `./source/Env.mc` file, templated from `./source/Env.mc.sample`.
