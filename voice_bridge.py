import socket
import json
import time

UDP_IP = "127.0.0.1"
UDP_PORT = 4242

print(f"Mars Terraform Voice Bridge (Python -> Godot)")
print(f"Targeting {UDP_IP}:{UDP_PORT}")
print("Type 'deploy x z' to send a command. Example: deploy 50 -20")
print("---------------------------------------------------------")

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

while True:
    try:
        user_input = input("Commander > ")
        parts = user_input.strip().split()
        
        if len(parts) >= 3 and parts[0].lower() == "deploy":
            try:
                x = float(parts[1])
                z = float(parts[2])
                
                payload = {
                    "command": "deploy_rover",
                    "parameters": {
                        "x": x,
                        "z": z
                    }
                }
                
                json_data = json.dumps(payload)
                sock.sendto(json_data.encode('utf-8'), (UDP_IP, UDP_PORT))
                print(f"Sent: {json_data}")
                
            except ValueError:
                print("Error: x and z must be numbers.")
        elif user_input.lower() in ["exit", "quit"]:
            break
        else:
            print("Unknown command. Try: deploy <x> <z>")
            
    except KeyboardInterrupt:
        break

print("Bridge closed.")
sock.close()
