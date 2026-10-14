# Load Balancing Lab Assignment Requirements

## 1. Assignment Overview

Requirement is about developing Bash Shell scripts and use the AWS CLI to deploy, configure, and manage a load balancing system consisting of virtual machines.

The system must include:
- One virtual machine acting as the Load Balancer.
- Two to three virtual machines acting as backend web servers.

## 2. Functional Requirements

### 2.1. Backend Management
Develop scripts to:
- Add backend servers to the Load Balancer cluster.
- Remove backend servers from the cluster.
- Manage the backend server pool dynamically.

### 2.2. Frontend Website Management
Develop scripts to:
- Add websites (frontends) to the system.
- Remove existing websites from the system.

### 2.3. Backend Monitoring and Cluster Reporting
Collect backend server metrics to assess their operational status and generate reports summarizing the overall health of the Load Balancer cluster.

The reports must include:

- **CPU, RAM, and Disk Usage:** Monitor resource utilization on each backend server.
- **Network Interfaces:** Collect information about network interfaces and their configurations.
- **Process and Thread Counts:** Report the current number of operating system processes and threads on each backend server.

## 3. Technical Requirements

- Use **Bash Shell** to implement automation and management scripts.
- Use the **AWS CLI** to create, configure, and manage AWS resources.
- Configure the Load Balancer and backend web servers to support HTTP traffic distribution.
- Provide scripts for backend management, frontend management, monitoring, and reporting.

## 4. Group Submission Requirements

Each group must submit the following deliverables:

1. **Bash Script Files:** All scripts used to create, configure, manage, monitor, and report on the load balancing system.
2. **Word Document:** A report containing:
   - Names and information of all group members.
   - Screenshots demonstrating the implementation and results of the assignment.

## 5. Expected Outcome

The completed system should demonstrate automated load balancing deployment, dynamic backend and frontend management, backend resource monitoring, and report generation using Bash Shell and the AWS CLI.