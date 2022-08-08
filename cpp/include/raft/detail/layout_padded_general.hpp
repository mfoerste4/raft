/*
 * Copyright (c) 2022, NVIDIA CORPORATION.
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

#include <raft/cudart_utils.h>
#include <raft/thirdparty/mdspan/include/experimental/mdspan>

#include <algorithm>
#include <array>
#include <numeric>

namespace std {
namespace experimental {

enum class StorageOrderType { column_major_t, row_major_t };

template <class Extents>
MDSPAN_INLINE_FUNCTION constexpr auto padded_row_major_strides(size_t Alignment,
                                                               Extents const& __exts)
  -> std::array<size_t, Extents::rank()>
{
  std::array<size_t, Extents::rank()> strides = std::array<size_t, Extents::rank()>{};
  size_t stride                               = 1;
  for (size_t r = Extents::rank() - 1; r > 0; r--) {
    strides[r] = stride;
    if (stride == 1) {
      stride *= std::max<size_t>(Alignment, raft::alignTo(__exts.extent(r), Alignment));
    } else {
      stride *= __exts.extent(r);
    }
  }
  strides[0] = stride;
  return strides;
}

template <class Extents>
MDSPAN_INLINE_FUNCTION constexpr auto padded_col_major_strides(size_t Alignment,
                                                               Extents const& __exts)
  -> std::array<size_t, Extents::rank()>
{
  std::array<size_t, Extents::rank()> strides = std::array<size_t, Extents::rank()>{};
  size_t stride                               = 1;
  for (size_t r = 0; r + 1 < Extents::rank(); r++) {
    strides[r] = stride;
    if (stride == 1) {
      stride *= std::max<size_t>(Alignment, raft::alignTo(__exts.extent(r), Alignment));
    } else {
      stride *= __exts.extent(r);
    }
  }
  strides[__exts.rank() - 1] = stride;
  return strides;
}

// keeping ByteAlignment as optional to allow testing
template <class ValueType, size_t ByteAlignment = 128>
struct padding {
  static_assert(std::is_same<remove_cv_t<ValueType>, ValueType>::value,
                "std::experimental::padding ValueType has to be provided without "
                "const or volatile specifiers.");
  static_assert(ByteAlignment % sizeof(ValueType) == 0 || sizeof(ValueType) % ByteAlignment == 0,
                "std::experimental::padding sizeof(ValueType) has to be multiple or "
                "divider of ByteAlignment.");
  static constexpr size_t value = std::max(ByteAlignment / sizeof(ValueType), 1ul);
};

// similar to layout_strided, but contiguous with padding in second smallest stride dimension
template <size_t Alignment, StorageOrderType StorageOrder = StorageOrderType::row_major_t>
struct layout_padded_general {
  static constexpr StorageOrderType storage_order = StorageOrder;
  static constexpr size_t element_alignment       = Alignment;

  template <class Extents>
  class mapping : public layout_stride::mapping<Extents> {
   public:
    // This could be a `requires`, but I think it's better and clearer as a `static_assert`.
    static_assert(detail::__is_extents_v<Extents>,
                  "std::experimental::layout_padded_general::mapping must be instantiated with a "
                  "specialization of std::experimental::extents.");
    // static_assert(Extents::rank() > 1, "std::experimental::layout_padded_general::mapping must be
    // instantiated with a Extents having rank > 1.");

    using size_type    = typename Extents::size_type;
    using extents_type = Extents;
    using layout_type  = layout_padded_general;
    using layout_stride::mapping<Extents>::mapping;

   private:
    //----------------------------------------------------------------------------

    template <class>
    friend class mapping;

   public:
    //--------------------------------------------------------------------------------

    MDSPAN_INLINE_FUNCTION_DEFAULTED constexpr mapping() noexcept                    = default;
    MDSPAN_INLINE_FUNCTION_DEFAULTED constexpr mapping(mapping const&) noexcept      = default;
    MDSPAN_INLINE_FUNCTION_DEFAULTED constexpr mapping(mapping&&) noexcept           = default;
    MDSPAN_INLINE_FUNCTION_DEFAULTED _MDSPAN_CONSTEXPR_14_DEFAULTED mapping& operator=(
      mapping const&) noexcept = default;
    MDSPAN_INLINE_FUNCTION_DEFAULTED _MDSPAN_CONSTEXPR_14_DEFAULTED mapping& operator=(
      mapping&&) noexcept = default;
    MDSPAN_INLINE_FUNCTION_DEFAULTED ~mapping() noexcept                             = default;

    MDSPAN_INLINE_FUNCTION
    constexpr mapping(Extents const& e) noexcept
      : layout_stride::mapping<Extents>{e,
                                        StorageOrder == StorageOrderType::row_major_t
                                          ? padded_row_major_strides(Alignment, e)
                                          : padded_col_major_strides(Alignment, e)}
    {
    }

    //--------------------------------------------------------------------------------
  };
};

}  // end namespace experimental
}  // end namespace std
