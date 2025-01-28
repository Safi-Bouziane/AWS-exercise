# The Greenfield Project

## Prerequisites

This project is written in Java, so install **Java 21**. The application can be shipped using **Docker**.

## Building

Build the application using `./mvnw package -Dnative` or by running `make application`. The use the Docker image, build an image using `docker build -t greenfield-project .` or run `make docker`.

## Running

Run the application using `docker run -p 8080:8080 greenfield-project`. When the application has started, a health endpoint is available on http://localhost:8080/q/health, metrics are available on http://localhost:8080/q/metrics.

## The Goal

Deploy the application as a web service reachable from the internet. You need to run it on an EKS cluster.
**as much as possible has to be provisioned through Infrastructure as Code**. You can use CloudFormation, Terraform or a tool of your own choice.

We will look at 4 pillars when reviewing the application

### Operational Excellence

How easy is it to deploy new changes and how easy is it for developers to troubleshoot the application. 

### Performance and Cost

How well is the workload scaled for tasks it needs to perform.

### Security

How is security handled on infrastructure level. Which ports are reachable? Which permissions does the application get? Which actions can I perform as the application?

### Reliability

Is the application built to scale and to recover from failures?