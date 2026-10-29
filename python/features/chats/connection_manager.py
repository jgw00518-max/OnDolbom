"""단일 FastAPI 프로세스의 공간별 연결 관리. DB 저장 후에만 전달한다."""
import asyncio
from dataclasses import dataclass, field
from collections.abc import Awaitable, Callable

from fastapi import WebSocket, HTTPException
from starlette.websockets import WebSocketDisconnect


@dataclass(eq=False)
class ChatConnection:
    socket: WebSocket
    token: str
    user_id: str
    expires_at: float
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def send(self, payload):
        async with self.lock:
            await asyncio.wait_for(self.socket.send_json(payload), timeout=5)

    async def close(self, code):
        try:
            async with self.lock:
                await asyncio.wait_for(self.socket.close(code=code), timeout=5)
        except (WebSocketDisconnect, RuntimeError, OSError, TimeoutError):
            pass


class ConnectionManager:
    def __init__(self):
        self.rooms: dict[str, set[ChatConnection]] = {}

    def add(self, room_id, connection):
        self.rooms.setdefault(room_id, set()).add(connection)

    def remove(self, room_id, connection):
        room = self.rooms.get(room_id)
        if room is not None:
            room.discard(connection)
            if not room:
                self.rooms.pop(room_id, None)

    async def close_member(self, room_id, user_id):
        # 다른 가족의 연결은 유지하고 종료 대상의 모든 기기 연결만 닫는다.
        peers = tuple(peer for peer in self.rooms.get(room_id, ()) if peer.user_id == user_id)
        for peer in peers:
            self.remove(room_id, peer)
        await asyncio.gather(*(peer.close(4403) for peer in peers), return_exceptions=True)

    async def close_room(self, room_id, *, code=4403):
        # 먼저 연결 목록에서 제외해 새 브로드캐스트에 포함되지 않게 한다.
        peers = tuple(self.rooms.pop(room_id, ()))
        # 연결 하나의 전송 오류로 이미 확정된 공간 삭제 응답을 실패시키지 않는다.
        await asyncio.gather(*(peer.close(code) for peer in peers), return_exceptions=True)

    async def broadcast(self, room_id, payload, authorize: Callable[[ChatConnection], Awaitable[None]]):
        async def deliver(connection):
            try:
                # 전송하지 않고 듣기만 하는 탈퇴·강퇴 사용자도 전달 직전에 차단한다.
                await authorize(connection)
                await connection.send(payload)
            except HTTPException as error:
                self.remove(room_id, connection)
                await connection.close(4401 if error.status_code == 401 else 4403 if error.status_code == 403 else 1013)
            except (WebSocketDisconnect, RuntimeError, OSError, TimeoutError):
                self.remove(room_id, connection)
                await connection.close(1013)

        await asyncio.gather(*(deliver(peer) for peer in tuple(self.rooms.get(room_id, ()))))


manager = ConnectionManager()
