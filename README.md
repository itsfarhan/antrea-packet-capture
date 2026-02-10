# Antrea Packet Capture Controller

A Kubernetes controller that performs on-demand packet captures for Pods using tcpdump. Think of it as an automated network traffic recorder for your Kubernetes pods.

## Overview

This controller runs as a DaemonSet on each node and watches for Pods with the `tcpdump.antrea.io` annotation. When detected, it starts a packet capture using tcpdump and stops when the annotation is removed.

## Features

- 🎯 On-demand packet capture via Pod annotations


## License

CC0 1.0 Universal
