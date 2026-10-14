## Description of Each File

- **`config.sh`**: Defines AWS configuration parameters, including the region, AMI, key pair, Security Group, and other shared settings.

- **`deploy.sh`**: Automatically creates backend EC2 instances and a Load Balancer, while passing User Data scripts to install and configure the system.

- **`web-server.sh`**: Installs and starts the Nginx web server on backend instances and creates web pages displaying server information.

- **`load-balancer.sh`**: Installs and configures Nginx on the Load Balancer to receive HTTP requests and distribute traffic across backend instances.

- **`monitor-backend.sh`**: Connects to backend instances via SSH to collect resource usage information, including CPU, memory, and disk utilization.

- **`network-report.sh`**: Collects network status and resource information from backend instances and consolidates the data into a report.

- **`lb-auto-adjust.sh`**: Monitors backend health and resource utilization, then automatically updates the Nginx configuration to adjust the list of backends handling incoming traffic.

- **`backend-list.txt`**: Stores the private IP addresses of backend instances for use by the Load Balancer and monitoring scripts. Automatically generated during deployment to store the private IP addresses of backend instances. It is used by the Load Balancer and monitoring scripts and does not need to be included in the repository.

- **`lab-info.txt`**: Stores AWS Lab environment information to facilitate resource lookup and deployment management.Automatically generated during deployment to store AWS Lab environment information for resource lookup and deployment management. It does not need to be included in the repository.

- **`manage-frontend.sh`**: Manages the frontend configuration on the Load Balancer, supporting the addition, removal, and listing of routes and configured static websites.

- **`manage-backend.sh`**: Manages the backend list used by the Load Balancer, supporting the addition, removal, and listing of backend instances participating in the load-balancing system.

