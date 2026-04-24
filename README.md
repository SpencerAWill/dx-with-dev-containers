# About

The goal of this repository is to demonstrate the capabilities of dev containers by creating a polyglot monorepo software system. To achieve that, this repository will be structured around 3 deliverable code units:
1. A web application (built on Tanstack Router + Vite + React 19)
2. A web API built on ASP.NET Core Web APIs (minimal APIs flavor)
3. An asynchronous Azure worker function project on C#

If this project were deployed on Azure, it would require several key dependencies:
1. Azure Storage Account (Blob Storage) - Host image blobs
2. Azure Service Bus - Message bus for events
3. Azure SQL Database - Relational database for everything

However, it is unclear how to set up an isolated development environment for this situation without having to provision actual Azure infrastructure to work in.

Luckily, there is a solution: Dev Container Composition + Azure emulation (images).