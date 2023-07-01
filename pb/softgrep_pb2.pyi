from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Chunk(_message.Message):
    __slots__ = ["content"]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    content: str
    def __init__(self, content: _Optional[str] = ...) -> None: ...

class Embedding(_message.Message):
    __slots__ = ["vec"]
    VEC_FIELD_NUMBER: _ClassVar[int]
    vec: _containers.RepeatedScalarFieldContainer[float]
    def __init__(self, vec: _Optional[_Iterable[float]] = ...) -> None: ...
