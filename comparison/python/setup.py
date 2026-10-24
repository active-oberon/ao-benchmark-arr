"""Build the video's Cython kernel with the installed C compiler and OpenMP."""
from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension, setup

root = Path(__file__).resolve().parents[1]
extension = Extension(
    "blazing_sum",
    [str(root / "python/blazing_sum.pyx")],
    include_dirs=[str(root / "common")],
    extra_compile_args=["-O3", "-march=native", "-fopenmp"],
    extra_link_args=["-fopenmp"],
)
setup(
    name="array-bench-cython",
    ext_modules=cythonize([extension], build_dir=str(root / "build/cython")),
)
