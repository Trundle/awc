import re
import subprocess
import sys
from enum import Enum, auto
from tempfile import NamedTemporaryFile


FILES_WITH_SHADERS = ["Sources/awc/Neon.swift"]


SHADER_NAME = re.compile(r"\b\w+(Fragment|Vertex)Source\b")


class Shader(Enum):
    FRAGMENT = auto()
    VERTEX = auto()


def _extract_shaders(lines_iter):
    lines = []
    shader = None
    name = None
    for line in lines_iter:
        if shader is None:
            if line.rstrip().endswith('"""'):
                if (name := SHADER_NAME.search(line)) is not None:
                    if name.group(1) == "Vertex":
                        shader = Shader.VERTEX
                    elif name.group(1) == "Fragment":
                        shader = Shader.FRAGMENT
                    name = name.group(0)
        elif line.rstrip().endswith('"""'):
            yield (
                name,
                shader,
                "\n".join(lines).encode("utf-8").decode("unicode-escape"),
            )
            shader = None
            lines = []
        else:
            lines.append(line)


def verify_file(path):
    has_errors = False
    with open(path) as source_file:
        for (name, shader, source) in _extract_shaders(source_file):
            suffix = ".vert" if shader == Shader.VERTEX else ".frag"
            with NamedTemporaryFile(
                mode="w", encoding="utf-8", suffix=suffix
            ) as tmpfile:
                tmpfile.write(source)
                tmpfile.flush()
                result = subprocess.run(
                    ["glslangValidator", tmpfile.name],
                    capture_output=True,
                    encoding="utf-8",
                )
                if result.returncode != 0:
                    print(f"Shader {name} has errors:", file=sys.stderr)
                    print(result.stdout, file=sys.stderr)
                    has_errors = True
    return has_errors


def main():
    return_code = 0
    for path in FILES_WITH_SHADERS:
        if verify_file(path):
            return_code = 1
    return return_code


sys.exit(main())
