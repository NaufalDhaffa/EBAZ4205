#!/usr/bin/env python3
"""UDP receiver for cam_stream: reassembles Y8 QVGA frames and displays them."""
import socket
import struct
import numpy as np
import cv2

LISTEN_PORT = 12345
FRAME_WIDTH = 320
# 480, not 240 -- the OV7670's vertical DCW/SCALING downscale doesn't
# actually take effect on real hardware (confirmed via VDMA's own S2MM
# status register), so it outputs the full 480-row sensor height. See the
# CAM_FRAME_HEIGHT comment in sw/apps/cam_stream/src/vdma.h.
FRAME_HEIGHT = 480
FRAME_SIZE = FRAME_WIDTH * FRAME_HEIGHT
PAYLOAD_MAX = 1016
HEADER_FMT = "<IHH"  # frame_id, packet_index, total_packets -- little-endian (Cortex-A9)
HEADER_LEN = struct.calcsize(HEADER_FMT)


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", LISTEN_PORT))
        print(f"Listening on UDP :{LISTEN_PORT}")

        frame_buf = bytearray(FRAME_SIZE)
        received = set()
        current_frame_id = None

        while True:
            data, _ = sock.recvfrom(2048)
            if len(data) < HEADER_LEN:
                continue

            frame_id, packet_index, total_packets = struct.unpack(HEADER_FMT, data[:HEADER_LEN])
            payload = data[HEADER_LEN:]

            if frame_id != current_frame_id:
                current_frame_id = frame_id
                received.clear()

            offset = packet_index * PAYLOAD_MAX
            end = offset + len(payload)
            if end > FRAME_SIZE:
                continue
            frame_buf[offset:end] = payload
            received.add(packet_index)

            if len(received) == total_packets:
                frame = np.frombuffer(bytes(frame_buf), dtype=np.uint8).reshape((FRAME_HEIGHT, FRAME_WIDTH))
                bgr = cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)
                cv2.imshow("cam_stream", bgr)
                if cv2.waitKey(1) & 0xFF == ord('q'):
                    break
                received.clear()
    finally:
        sock.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
