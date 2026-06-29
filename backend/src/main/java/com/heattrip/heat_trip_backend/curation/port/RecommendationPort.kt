package com.heattrip.heat_trip_backend.curation.port

import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendRequest
import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendResponse

interface RecommendationPort {
    fun getRecommendation(request: LlmRecommendRequest): LlmRecommendResponse?
}