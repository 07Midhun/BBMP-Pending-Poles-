import os
import socket
import sys
import webbrowser
from http.server import HTTPServer, SimpleHTTPRequestHandler

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def find_web_dir():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    option1 = os.path.join(current_dir, "mobile", "build", "web")
    option2 = os.path.join(current_dir, "build", "web")
    
    if os.path.isdir(option1):
        return option1
    elif os.path.isdir(option2):
        return option2
    return option1

class CustomHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        web_dir = find_web_dir()
        super().__init__(*args, directory=web_dir, **kwargs)

def main():
    port = 8080
    host_ip = get_local_ip()
    web_dir = find_web_dir()
    
    print("\n" + "=" * 65)
    print("  🚀 BBMP PENDING POLES — SCHNELL IOT WEB APPLICATION")
    print("=" * 65)
    print(f"  👉 Clickable Local Link   : http://localhost:{port}")
    print(f"  👉 Clickable Loopback Link: http://127.0.0.1:{port}")
    print(f"  👉 Mobile Network Link   : http://{host_ip}:{port}")
    print(f"  ⚡ Backend API Docs       : http://localhost:8000/docs")
    print("=" * 65)
    print(f"  Serving Directory        : {web_dir}\n")

    try:
        webbrowser.open(f"http://localhost:{port}")
    except Exception:
        pass

    server_address = ("0.0.0.0", port)
    httpd = HTTPServer(server_address, CustomHandler)
    print(f"Serving Flutter Web Application on 0.0.0.0:{port} ... (Press Ctrl+C to stop)\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")

if __name__ == "__main__":
    main()
