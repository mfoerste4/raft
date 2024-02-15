/*
 * Copyright (c) 2024, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <cub/block/block_scan.cuh>
#include <raft/linalg/unary_op.cuh>
#include <raft/matrix/detail/select_warpsort.cuh>  // matrix::detail::select::warpsort::warp_sort_distributed

namespace raft::neighbors::detail::ivf {

/**
 * Default value returned by `search` when the `n_probes` is too small and top-k is too large.
 * One may encounter it if the combined size of probed clusters is smaller than the requested
 * number of results per query.
 */
template <typename IdxT>
constexpr static IdxT kOutOfBoundsRecord = std::numeric_limits<IdxT>::max();

template <typename T, typename IdxT>
struct dummy_block_sort_t {
  using queue_t = matrix::detail::select::warpsort::warp_sort_distributed<WarpSize, true, T, IdxT>;
  template <typename... Args>
  __device__ dummy_block_sort_t(int k, Args...){};
};

/**
 * For each query, we calculate a cumulative sum of the cluster sizes that we probe, and return that
 * in chunk_indices. Essentially this is a segmented inclusive scan of the cluster sizes. The total
 * number of samples per query (sum of the cluster sizes that we probe) is returned in n_samples.
 */
template <int BlockDim>
__launch_bounds__(BlockDim) RAFT_KERNEL
  calc_chunk_indices_kernel(uint32_t n_probes,
                            const uint32_t* cluster_sizes,      // [n_clusters]
                            const uint32_t* clusters_to_probe,  // [n_queries, n_probes]
                            uint32_t* chunk_indices,            // [n_queries, n_probes]
                            uint32_t* n_samples                 // [n_queries]
  )
{
  using block_scan = cub::BlockScan<uint32_t, BlockDim>;
  __shared__ typename block_scan::TempStorage shm;

  // locate the query data
  clusters_to_probe += n_probes * blockIdx.x;
  chunk_indices += n_probes * blockIdx.x;

  // block scan
  const uint32_t n_probes_aligned = Pow2<BlockDim>::roundUp(n_probes);
  uint32_t total                  = 0;
  for (uint32_t probe_ix = threadIdx.x; probe_ix < n_probes_aligned; probe_ix += BlockDim) {
    auto label = probe_ix < n_probes ? clusters_to_probe[probe_ix] : 0u;
    auto chunk = probe_ix < n_probes ? cluster_sizes[label] : 0u;
    if (threadIdx.x == 0) { chunk += total; }
    block_scan(shm).InclusiveSum(chunk, chunk, total);
    __syncthreads();
    if (probe_ix < n_probes) { chunk_indices[probe_ix] = chunk; }
  }
  // save the total size
  if (threadIdx.x == 0) { n_samples[blockIdx.x] = total; }
}

struct calc_chunk_indices {
 public:
  struct configured {
    void* kernel;
    dim3 block_dim;
    dim3 grid_dim;
    uint32_t n_probes;

    inline void operator()(const uint32_t* cluster_sizes,
                           const uint32_t* clusters_to_probe,
                           uint32_t* chunk_indices,
                           uint32_t* n_samples,
                           rmm::cuda_stream_view stream)
    {
      void* args[] =  // NOLINT
        {&n_probes, &cluster_sizes, &clusters_to_probe, &chunk_indices, &n_samples};
      RAFT_CUDA_TRY(cudaLaunchKernel(kernel, grid_dim, block_dim, args, 0, stream));
    }
  };

  static inline auto configure(uint32_t n_probes, uint32_t n_queries) -> configured
  {
    return try_block_dim<1024>(n_probes, n_queries);
  }

 private:
  template <int BlockDim>
  static auto try_block_dim(uint32_t n_probes, uint32_t n_queries) -> configured
  {
    if constexpr (BlockDim >= WarpSize * 2) {
      if (BlockDim >= n_probes * 2) { return try_block_dim<(BlockDim / 2)>(n_probes, n_queries); }
    }
    return {reinterpret_cast<void*>(calc_chunk_indices_kernel<BlockDim>),
            dim3(BlockDim, 1, 1),
            dim3(n_queries, 1, 1),
            n_probes};
  }
};

/**
 * Look up the chunk id corresponding to the sample index.
 *
 * Each query vector was compared to all the vectors from n_probes clusters, and sample_ix is an
 * ordered number of one of such vectors. This function looks up to which chunk it belongs,
 * and returns the index within the chunk (which is also an index within a cluster).
 *
 * @param[inout] sample_ix
 *   input: the offset of the sample in the batch;
 *   output: the offset inside the chunk (probe) / selected cluster.
 * @param[in] n_probes number of probes
 * @param[in] chunk_indices offsets of the chunks within the batch [n_probes]
 * @return chunk index (== n_probes when the input index is not in the valid range,
 *    which can happen if there is not enough data to output in the selected clusters).
 */
__device__ inline auto find_chunk_ix(uint32_t& sample_ix,  // NOLINT
                                     uint32_t n_probes,
                                     const uint32_t* chunk_indices) -> uint32_t
{
  uint32_t ix_min = 0;
  uint32_t ix_max = n_probes;
  do {
    uint32_t i = (ix_min + ix_max) / 2;
    if (chunk_indices[i] <= sample_ix) {
      ix_min = i + 1;
    } else {
      ix_max = i;
    }
  } while (ix_min < ix_max);
  if (ix_min > 0) { sample_ix -= chunk_indices[ix_min - 1]; }
  return ix_min;
}

template <int BlockDim, typename IdxT1, typename IdxT2 = uint32_t>
__launch_bounds__(BlockDim) RAFT_KERNEL
  postprocess_neighbors_kernel(IdxT1* neighbors_out,               // [n_queries, topk]
                               const IdxT2* neighbors_in,          // [n_queries, topk]
                               const IdxT1* const* db_indices,     // [n_clusters][..]
                               const uint32_t* clusters_to_probe,  // [n_queries, n_probes]
                               const uint32_t* chunk_indices,      // [n_queries, n_probes]
                               uint32_t n_queries,
                               uint32_t n_probes,
                               uint32_t topk)
{
  const uint64_t i        = threadIdx.x + BlockDim * uint64_t(blockIdx.x);
  const uint32_t query_ix = i / uint64_t(topk);
  if (query_ix >= n_queries) { return; }
  const uint32_t k = i % uint64_t(topk);
  neighbors_in += query_ix * topk;
  neighbors_out += query_ix * topk;
  chunk_indices += query_ix * n_probes;
  clusters_to_probe += query_ix * n_probes;
  uint32_t data_ix        = neighbors_in[k];
  const uint32_t chunk_ix = find_chunk_ix(data_ix, n_probes, chunk_indices);
  const bool valid        = chunk_ix < n_probes;
  neighbors_out[k] =
    valid ? db_indices[clusters_to_probe[chunk_ix]][data_ix] : kOutOfBoundsRecord<IdxT1>;
}

/**
 * Transform found sample indices into the corresponding database indices
 * (as stored in index.indices()).
 * The sample indices are the record indices as they appear in the database view formed by the
 * probed clusters / defined by the `chunk_indices`.
 * We assume the searched sample sizes (for a single query) fit into `uint32_t`.
 */
template <typename IdxT1, typename IdxT2 = uint32_t>
void postprocess_neighbors(IdxT1* neighbors_out,               // [n_queries, topk]
                           const IdxT2* neighbors_in,          // [n_queries, topk]
                           const IdxT1* const* db_indices,     // [n_clusters][..]
                           const uint32_t* clusters_to_probe,  // [n_queries, n_probes]
                           const uint32_t* chunk_indices,      // [n_queries, n_probes]
                           uint32_t n_queries,
                           uint32_t n_probes,
                           uint32_t topk,
                           rmm::cuda_stream_view stream)
{
  constexpr int kPNThreads = 256;
  const int pn_blocks      = raft::div_rounding_up_unsafe<size_t>(n_queries * topk, kPNThreads);
  postprocess_neighbors_kernel<kPNThreads, IdxT1, IdxT2>
    <<<pn_blocks, kPNThreads, 0, stream>>>(neighbors_out,
                                           neighbors_in,
                                           db_indices,
                                           clusters_to_probe,
                                           chunk_indices,
                                           n_queries,
                                           n_probes,
                                           topk);
}

/**
 * Post-process the scores depending on the metric type;
 * translate the element type if necessary.
 */
template <typename ScoreInT, typename ScoreOutT = float>
void postprocess_distances(ScoreOutT* out,      // [n_queries, topk]
                           const ScoreInT* in,  // [n_queries, topk]
                           distance::DistanceType metric,
                           uint32_t n_queries,
                           uint32_t topk,
                           float scaling_factor,
                           rmm::cuda_stream_view stream)
{
  size_t len = size_t(n_queries) * size_t(topk);
  switch (metric) {
    case distance::DistanceType::L2Unexpanded:
    case distance::DistanceType::L2Expanded: {
      linalg::unaryOp(
        out,
        in,
        len,
        raft::compose_op(raft::mul_const_op<ScoreOutT>{scaling_factor * scaling_factor},
                         raft::cast_op<ScoreOutT>{}),
        stream);
    } break;
    case distance::DistanceType::L2SqrtUnexpanded:
    case distance::DistanceType::L2SqrtExpanded: {
      linalg::unaryOp(out,
                      in,
                      len,
                      raft::compose_op{raft::mul_const_op<ScoreOutT>{scaling_factor},
                                       raft::sqrt_op{},
                                       raft::cast_op<ScoreOutT>{}},
                      stream);
    } break;
    case distance::DistanceType::InnerProduct: {
      linalg::unaryOp(
        out,
        in,
        len,
        raft::compose_op(raft::mul_const_op<ScoreOutT>{-scaling_factor * scaling_factor},
                         raft::cast_op<ScoreOutT>{}),
        stream);
    } break;
    default: RAFT_FAIL("Unexpected metric.");
  }
}

}  // namespace raft::neighbors::detail::ivf
