import ray
from ray.runtime_env import RuntimeEnv

runtime_env = RuntimeEnv(
    conda="""
name: env-name
channels:
  - nvidia
  - pytorch
  - conda-forge
  - defaults
dependencies:
  - python=3.7
  - codecov
  - pytorch
  - torchvision
  - torchaudio
  - pytorch-cuda=11.8
  - numpy
"""
)

ray.init(runtime_env=runtime_env)

@ray.remote(num_gpus=1)
def check_gpu():
    import torch
    print(torch.cuda.is_available())

check_gpu.remote()

