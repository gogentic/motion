#!/bin/bash

echo "Stopping MOTION Services"
echo "========================"

if [ -f ".pids" ]; then
    source .pids
    
    if [ ! -z "$COMFYUI_PID" ] && ps -p $COMFYUI_PID > /dev/null; then
        echo "Stopping ComfyUI (PID: $COMFYUI_PID)..."
        kill $COMFYUI_PID
    fi
    
    if [ ! -z "$API_PID" ] && ps -p $API_PID > /dev/null; then
        echo "Stopping API Service (PID: $API_PID)..."
        kill $API_PID
    fi
    
    rm .pids
    echo "Services stopped"
else
    echo "No running services found (.pids file missing)"
    echo "You can manually stop services with: ps aux | grep -E 'main.py|api_service.py'"
fi