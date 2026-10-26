import Foundation
import PhoenixValleyCore
import SwiftUI

struct RoadStructureReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: RoadDocumentStore
    let review: RoadStructureReviewRecord
    @State private var selections: [String: RoadStructureType]

    init(document: RoadDocumentStore, review: RoadStructureReviewRecord) {
        self.document = document
        self.review = review
        _selections = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: review.plan.candidates.map {
                    ($0.id, $0.structure)
                }
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("道路", value: review.plan.roadKind.displayName)
                    LabeledContent(
                        "分析长度",
                        value: distanceDescription(review.plan.totalLength)
                    )
                    LabeledContent(
                        "采样点",
                        value: "\(review.plan.samples.count)"
                    )
                } header: {
                    Text("自动结构分析")
                } footer: {
                    Text("虚线高亮显示建议区段；桥梁、隧道与高架会作为独立结构保存。")
                }

                ForEach(review.plan.candidates) { candidate in
                    Section {
                        Picker(
                            "处理方式",
                            selection: selectionBinding(for: candidate)
                        ) {
                            ForEach(allowedStructures(for: candidate), id: \.self) { structure in
                                Text(structure.displayName).tag(structure)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("structure-choice-\(candidate.id)")

                        LabeledContent(
                            "沿线范围",
                            value: chainageDescription(candidate.evidence.sampleRange)
                        )
                        LabeledContent(
                            "触发条件",
                            value: candidate.evidence.triggers
                                .map(\.displayName)
                                .sorted()
                                .joined(separator: "、")
                        )
                        LabeledContent(
                            "原地表最大纵坡",
                            value: candidate.evidence.metrics.maximumAbsoluteGrade
                                .formatted(.percent.precision(.fractionLength(1)))
                        )
                        if let structure = engineeringStructure(for: candidate) {
                            engineeringDetails(structure)
                        }
                        if !candidate.evidence.relatedRoadIDs.isEmpty {
                            LabeledContent(
                                "关联道路",
                                value: "\(candidate.evidence.relatedRoadIDs.count) 条"
                            )
                        }
                    } header: {
                        Label(candidate.structure.displayName, systemImage: candidate.structure.symbol)
                    } footer: {
                        Text(transitionDescription(for: candidate))
                    }
                }

                if !review.plan.crossingSuggestions.isEmpty {
                    Section("道路交叉") {
                        ForEach(review.plan.crossingSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.treatment.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(
                                    "交角 \((suggestion.crossingAngle * 180 / .pi).formatted(.number.precision(.fractionLength(0))))° · "
                                        + "既有层级 \(suggestion.existingLevel.displayName)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("确认道路结构")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                reviewActions
                    .padding()
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消绘制", role: .destructive) {
                        document.discardPendingRoad(id: review.id)
                        dismiss()
                    }
                }
            }
        }
    }

    private var reviewActions: some View {
        let construction = constructionEvaluation
        return VStack(alignment: .leading, spacing: 10) {
            if engineeringEvaluation.hasErrors {
                Label(
                    "当前方案有 \(engineeringEvaluation.issues.count) 项工程约束未满足",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier("structure-engineering-error-summary")
            }
            if !construction.isFeasible {
                Label(
                    "仍有 \(construction.issues.count) 个地面道路或高架区间不可施工",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier(
                    "structure-construction-error-summary"
                )
            }

            HStack {
                Button("保留原道路") {
                    document.rejectStructureReview(id: review.id)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reject-structure-plan")

                Spacer()

                Button("应用方案") {
                    if document.applyStructureReview(
                        id: review.id,
                        decisions: decisions
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    engineeringEvaluation.hasErrors
                        || !construction.isFeasible
                )
                .accessibilityIdentifier("apply-structure-plan")
            }
        }
    }

    private var decisions: [AutoStructureDecision] {
        review.plan.candidates.map { candidate in
            let selection = selections[candidate.id] ?? candidate.structure
            let resolution: AutoStructureDecisionResolution
            if selection == candidate.structure {
                resolution = .accept
            } else if selection == .ground {
                resolution = .reject
            } else {
                resolution = .replace(with: selection)
            }
            return AutoStructureDecision(
                candidateID: candidate.id,
                resolution: resolution
            )
        }
    }

    private var engineeringEvaluation: RoadEngineeringEvaluation {
        RoadEngineeringPlanner.evaluate(
            plan: review.plan,
            decisions: decisions,
            terrain: document.project.terrain,
            mapScale: document.project.mapScale
        )
    }

    private var constructionEvaluation: RoadConstructionFeasibilityReport {
        let roads = review.plan.resolving(decisions).enumerated().compactMap {
            index, span -> RoadSegment? in
            guard span.points.count >= 2 else { return nil }
            return RoadSegment(
                id: index == 0 ? review.plan.sourceEdgeID : UUID(),
                kind: span.roadKind,
                structure: span.structure,
                points: span.points,
                sourceRoadID: review.plan.sourceRoadID
            )
        }
        return RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: roads,
            terrain: document.project.terrain,
            mapScale: document.project.mapScale
        )
    }

    private func engineeringStructure(
        for candidate: AutoStructureCandidate
    ) -> RoadEngineeringStructure? {
        engineeringEvaluation.structure(forCandidateID: candidate.id)
    }

    @ViewBuilder
    private func engineeringDetails(_ structure: RoadEngineeringStructure) -> some View {
        let report = structure.report
        LabeledContent(
            "结构长度",
            value: lengthRuleDescription(report)
        )
        LabeledContent(
            structure.structure == .bridge ? "桥面纵坡" : "隧道轴线纵坡",
            value: gradeRuleDescription(
                measured: report.structureGrade,
                limit: report.maximumStructureGrade
            )
        )
        LabeledContent(
            "入口引道纵坡",
            value: gradeRuleDescription(
                measured: abs(structure.endpoints.first?.approachGrade ?? 0),
                limit: report.maximumApproachGrade
            )
        )
        LabeledContent(
            "出口引道纵坡",
            value: gradeRuleDescription(
                measured: abs(structure.endpoints.last?.approachGrade ?? 0),
                limit: report.maximumApproachGrade
            )
        )
        if structure.structure == .bridge {
            LabeledContent(
                "桥墩布置",
                value: "\(structure.bridgePiers.count) 座 · 最大跨径 \(Int((report.maximumBridgeSpanMeters ?? 0).rounded())) m"
            )
        }
        if let cover = report.minimumTunnelCoverMeters {
            LabeledContent(
                "最小覆土",
                value: "\(cover.formatted(.number.precision(.fractionLength(1)))) m"
            )
        }
        ForEach(report.issues) { issue in
            Label(
                issue.displayDescription,
                systemImage: "exclamationmark.octagon.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("structure-constraint-\(issue.id)")
        }
    }

    private func lengthRuleDescription(_ report: RoadEngineeringReport) -> String {
        let measured = Int(report.structureLengthMeters.rounded())
        let minimum = Int(report.minimumLengthMeters.rounded())
        if let maximum = report.maximumLengthMeters {
            return "\(measured) m（允许 \(minimum)–\(Int(maximum.rounded())) m）"
        }
        return "\(measured) m（至少 \(minimum) m）"
    }

    private func gradeRuleDescription(measured: Double, limit: Double) -> String {
        let measuredText = measured.formatted(
            .percent.precision(.fractionLength(1))
        )
        let limitText = limit.formatted(
            .percent.precision(.fractionLength(1))
        )
        return "\(measuredText)（上限 \(limitText)）"
    }

    private func selectionBinding(
        for candidate: AutoStructureCandidate
    ) -> Binding<RoadStructureType> {
        Binding(
            get: { selections[candidate.id] ?? candidate.structure },
            set: { selections[candidate.id] = $0 }
        )
    }

    private func allowedStructures(
        for candidate: AutoStructureCandidate
    ) -> [RoadStructureType] {
        if candidate.evidence.triggers.contains(.water) {
            return [.bridge, .tunnel]
        }
        return RoadStructureType.allCases
    }

    private func chainageDescription(_ range: StructureSampleRange) -> String {
        let start = document.project.mapScale.meters(
            forCanvasDistance: range.startDistance
        )
        let end = document.project.mapScale.meters(
            forCanvasDistance: range.endDistance
        )
        return "\(Int(start.rounded()))–\(Int(end.rounded())) m"
    }

    private func distanceDescription(_ canvasDistance: Double) -> String {
        let meters = document.project.mapScale.meters(
            forCanvasDistance: canvasDistance
        )
        return "\(Int(meters.rounded())) m"
    }

    private func transitionDescription(
        for candidate: AutoStructureCandidate
    ) -> String {
        let entranceGrade = candidate.entrance.approachGrade
            .formatted(.percent.precision(.fractionLength(1)))
        let exitGrade = candidate.exit.approachGrade
            .formatted(.percent.precision(.fractionLength(1)))
        return "入口纵坡 \(entranceGrade)，出口纵坡 \(exitGrade)。"
    }
}

extension RoadEngineeringConstraintIssue {
    var displayDescription: String {
        switch kind {
        case .belowMinimumLength:
            "结构长度 \(formattedValue(measuredValue))，低于 \(formattedValue(limitValue))"
        case .aboveMaximumBridgeLength:
            "桥梁长度 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .structureGradeTooSteep:
            "结构纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .entranceApproachTooSteep:
            "入口引道纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .exitApproachTooSteep:
            "出口引道纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .bridgeheadInWater:
            location == .entrance ? "入口桥头位于水域" : "出口桥头位于水域"
        case .tunnelPortalInWater:
            location == .entrance ? "入口洞口位于水域" : "出口洞口位于水域"
        case .insufficientTunnelCover:
            "最小覆土 \(formattedValue(measuredValue))，低于 \(formattedValue(limitValue))"
        case .bridgeDeckBelowTerrain:
            "桥面与地形相交 \(formattedValue(measuredValue))"
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch unit {
        case .meters:
            "\(value.formatted(.number.precision(.fractionLength(1)))) m"
        case .grade:
            value.formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

extension RoadConstructionIssue {
    var displayDescription: String {
        let chainage = "\(startChainageMeters.formatted(.number.precision(.fractionLength(0))))"
            + "–\(endChainageMeters.formatted(.number.precision(.fractionLength(0)))) m"
        switch kind {
        case .localGradeAboveLimit:
            return "\(roadKind.displayName) \(chainage)：局部纵坡 "
                + measuredValue.formatted(.percent.precision(.fractionLength(1)))
                + "，上限 "
                + limitValue.formatted(.percent.precision(.fractionLength(1)))
        case .groundRoadInWater:
            return "\(roadKind.displayName) \(chainage)：地面道路进入水域"
        case .elevatedAxisGradeAboveLimit:
            return "\(roadKind.displayName) \(chainage)：高架轴线纵坡 "
                + measuredValue.formatted(.percent.precision(.fractionLength(1)))
                + "，上限 "
                + limitValue.formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

extension RoadStructureType {
    var symbol: String {
        switch self {
        case .ground:
            "road.lanes"
        case .bridge:
            "water.waves"
        case .tunnel:
            "mountain.2"
        case .elevated:
            "arrow.up.forward"
        }
    }
}

extension AutoStructureTrigger {
    var displayName: String {
        switch self {
        case .water:
            "水域"
        case .steepGrade:
            "纵坡过陡"
        case .mountainRelief:
            "山体起伏"
        case .tunnelLengthAdvantage:
            "隧道缩短路线"
        case .roadCrossing:
            "道路交叉"
        case .roadPriority:
            "道路等级"
        case .crossingAngle:
            "交叉角度"
        case .existingVerticalSeparation:
            "既有分层"
        }
    }
}

extension RoadCrossingTreatment {
    var displayName: String {
        switch self {
        case .atGrade:
            "平面路口"
        case .elevated:
            "建议高架"
        case .interchange:
            "建议立交"
        case .preserveExistingSeparation:
            "保持既有分层"
        case .deferToPrimaryStructure:
            "服从连续桥隧结构"
        }
    }
}

extension RoadLevel {
    var displayName: String {
        switch self {
        case .tunnel:
            "隧道"
        case .ground:
            "地面"
        case .elevated:
            "高架"
        }
    }
}
