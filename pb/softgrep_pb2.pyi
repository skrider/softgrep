from google.protobuf import timestamp_pb2 as _timestamp_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class Chunk(_message.Message):
    __slots__ = ["content"]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    content: str
    def __init__(self, content: _Optional[str] = ...) -> None: ...

class Embedding(_message.Message):
    __slots__ = ["vec"]
    class Vector(_message.Message):
        __slots__ = ["elem"]
        ELEM_FIELD_NUMBER: _ClassVar[int]
        elem: _containers.RepeatedScalarFieldContainer[float]
        def __init__(self, elem: _Optional[_Iterable[float]] = ...) -> None: ...
    VEC_FIELD_NUMBER: _ClassVar[int]
    vec: Embedding.Vector
    def __init__(self, vec: _Optional[_Union[Embedding.Vector, _Mapping]] = ...) -> None: ...
