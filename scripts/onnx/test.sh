#!/bin/bash

set -ex

UNKNOWN=()

# defaults
PARALLEL=1

while [[ $# -gt 0 ]]
do
    arg="$1"
    case $arg in
        -p|--parallel)
            PARALLEL=1
            shift # past argument
            ;;
        *) # unknown option
            UNKNOWN+=("$1") # save it in an array for later
            shift # past argument
            ;;
    esac
done
set -- "${UNKNOWN[@]}" # leave UNKNOWN

if [[ $PARALLEL == 1 ]]; then
    pip install pytest-xdist
fi

pip install pytest scipy hypothesis # these may not be necessary
pip install pytest-cov # installing since `coverage run -m pytest ..` doesn't work
pip install -e tools/coverage_plugins_package # allows coverage to run w/o failing due to a missing plug-in

# realpath might not be available on MacOS
script_path=$(python -c "import os; import sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")
top_dir=$(dirname $(dirname $(dirname "$script_path")))
test_paths=(
    "$top_dir/test/onnx"
)

args=()
args+=("-v")
args+=("--cov")
args+=("--cov-report")
args+=("xml:test/coverage.xml")
args+=("--cov-append")

args_parallel=()
if [[ $PARALLEL == 1 ]]; then
  args_parallel+=("-n")
  args_parallel+=("auto")
fi

# onnxruntime only support py3
# "Python.h" not found in py2, needed by TorchScript custom op compilation.
if [[ "${SHARD_NUMBER}" == "1" ]]; then
  # These exclusions are for tests that take a long time / a lot of GPU
  # memory to run; they should be passing (and you will test them if you
  # run them locally
  pytest "${args[@]}" "${args_parallel[@]}" \
    --ignore "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime.py" \
    --ignore "$top_dir/test/onnx/test_custom_ops.py" \
    --ignore "$top_dir/test/onnx/test_models_onnxruntime.py" \
    --ignore "$top_dir/test/onnx/test_utility_funs.py" \
    --ignore "$top_dir/test/onnx/test_pytorch_onnx_caffe2.py" \
    --ignore "$top_dir/test/onnx/test_pytorch_onnx_shape_inference.py" \
    --ignore "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime_cuda.py" \
    --ignore "$top_dir/test/onnx/test_pytorch_onnx_caffe2_quantized.py" \
    "${test_paths[@]}"

  # Tests that cannot run in parallel.
  pytest "${args[@]}" \
    "$top_dir/test/onnx/test_onnx_export.py" \
    "$top_dir/test/onnx/test_models_onnxruntime.py"

  pytest "${args[@]}" "${args_parallel[@]}" \
    "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime.py::TestONNXRuntime_opset7" \
    "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime.py::TestONNXRuntime_opset8" \
    "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime.py::TestONNXRuntime_opset9" \
    "$top_dir/test/onnx/test_custom_ops.py" \
    "$top_dir/test/onnx/test_utility_funs.py" \
    "$top_dir/test/onnx/test_pytorch_onnx_shape_inference.py" \
    "$top_dir/test/onnx/test_pytorch_onnx_caffe2.py" \
    "$top_dir/test/onnx/test_pytorch_onnx_caffe2_quantized.py"
fi

if [[ "${SHARD_NUMBER}" == "2" ]]; then
  # Update the loop for new opsets
  for i in $(seq 10 16); do
    pytest "${args[@]}" "${args_parallel[@]}"\
      "$top_dir/test/onnx/test_pytorch_onnx_onnxruntime.py::TestONNXRuntime_opset$i"
  done
fi

# Our CI expects both coverage.xml and .coverage to be within test/
if [ -d .coverage ]; then
  mv .coverage test/.coverage
fi
