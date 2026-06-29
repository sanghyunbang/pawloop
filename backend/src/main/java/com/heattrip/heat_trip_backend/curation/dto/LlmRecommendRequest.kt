package com.heattrip.heat_trip_backend.curation.dto

import com.fasterxml.jackson.annotation.JsonProperty

data class LlmRecommendRequest(
    val pleasure: Double = 0.0,
    val arousal: Double = 0.0,
    val dominance: Double = 0.0,
    val energy: Double = 0.0,
    val social: Double = 0.0,

    @get:JsonProperty("moodKey")
    val moodKey: String? = null,

    @get:JsonProperty("purpose_keywords")
    val purposeKeywords: List<String>? = null,

    val notes: String? = null
) {
}