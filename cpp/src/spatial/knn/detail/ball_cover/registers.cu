/*
 * Copyright (c) 2021-2024, NVIDIA CORPORATION.
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

#include <raft/spatial/knn/detail/ball_cover/registers-inl.cuh>

#define instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one(                 \
  Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx, Mdims)                           \
  template void raft::spatial::knn::detail::                                      \
    rbc_low_dim_pass_one<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx, Mdims>(   \
      raft::resources const& handle,                                              \
      const BallCoverIndex<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>& index, \
      const Mvalue_t* query,                                                      \
      const Mvalue_int n_query_rows,                                              \
      Mvalue_int k,                                                               \
      const Mvalue_idx* R_knn_inds,                                               \
      const Mvalue_t* R_knn_dists,                                                \
      raft::spatial::knn::detail::DistFunc<Mvalue_t, Mvalue_int>& dfunc,          \
      Mvalue_idx* inds,                                                           \
      Mvalue_t* dists,                                                            \
      float weight,                                                               \
      Mvalue_int* dists_counter)

#define instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two(                 \
  Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx, Mdims)                           \
  template void raft::spatial::knn::detail::                                      \
    rbc_low_dim_pass_two<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx, Mdims>(   \
      raft::resources const& handle,                                              \
      const BallCoverIndex<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>& index, \
      const Mvalue_t* query,                                                      \
      const Mvalue_int n_query_rows,                                              \
      Mvalue_int k,                                                               \
      const Mvalue_idx* R_knn_inds,                                               \
      const Mvalue_t* R_knn_dists,                                                \
      raft::spatial::knn::detail::DistFunc<Mvalue_t, Mvalue_int>& dfunc,          \
      Mvalue_idx* inds,                                                           \
      Mvalue_t* dists,                                                            \
      float weight,                                                               \
      Mvalue_int* dists_counter)

#define instantiate_raft_spatial_knn_detail_rbc_eps_pass(                                  \
  Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx)                                           \
  template void                                                                            \
  raft::spatial::knn::detail::rbc_eps_pass<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>( \
    raft::resources const& handle,                                                         \
    const BallCoverIndex<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>& index,            \
    const Mvalue_t* query,                                                                 \
    const Mvalue_int n_query_rows,                                                         \
    Mvalue_t eps,                                                                          \
    const Mvalue_t* R_dists,                                                               \
    raft::spatial::knn::detail::DistFunc<Mvalue_t, Mvalue_int>& dfunc,                     \
    bool* adj,                                                                             \
    Mvalue_idx* vd);                                                                       \
                                                                                           \
  template void                                                                            \
  raft::spatial::knn::detail::rbc_eps_pass<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>( \
    raft::resources const& handle,                                                         \
    const BallCoverIndex<Mvalue_idx, Mvalue_t, Mvalue_int, Mmatrix_idx>& index,            \
    const Mvalue_t* query,                                                                 \
    const Mvalue_int n_query_rows,                                                         \
    Mvalue_t eps,                                                                          \
    const Mvalue_t* R_dists,                                                               \
    raft::spatial::knn::detail::DistFunc<Mvalue_t, Mvalue_int>& dfunc,                     \
    Mvalue_idx* ia,                                                                        \
    Mvalue_idx* ja,                                                                        \
    Mvalue_idx* vd)

instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one(
  std::int64_t, float, std::int64_t, std::int64_t, 2);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one(
  std::int64_t, float, std::int64_t, std::int64_t, 3);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one(
  std::int64_t, double, std::int64_t, std::int64_t, 2);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one(
  std::int64_t, double, std::int64_t, std::int64_t, 3);

instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two(
  std::int64_t, float, std::int64_t, std::int64_t, 2);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two(
  std::int64_t, float, std::int64_t, std::int64_t, 3);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two(
  std::int64_t, double, std::int64_t, std::int64_t, 2);
instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two(
  std::int64_t, double, std::int64_t, std::int64_t, 3);

instantiate_raft_spatial_knn_detail_rbc_eps_pass(std::int64_t, float, std::int64_t, std::int64_t);
instantiate_raft_spatial_knn_detail_rbc_eps_pass(std::int64_t, double, std::int64_t, std::int64_t);

#undef instantiate_raft_spatial_knn_detail_rbc_eps_pass
#undef instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_two
#undef instantiate_raft_spatial_knn_detail_rbc_low_dim_pass_one
