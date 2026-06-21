import SwiftUI

// MARK: - Goals Management View (Simplified)
struct GoalsManagementView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var newGoalText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Add Goal Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add Mission Objective")
                                .font(.headline)
                                .foregroundColor(themeManager.textColor)

                            HStack {
                                TextField("Enter objective...", text: $newGoalText)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())

                                Button(action: addGoal) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(themeManager.accentColor)
                                }
                                .disabled(newGoalText.isEmpty)
                            }
                        }
                        .padding()
                        .background(themeManager.secondaryBackgroundColor)
                        .cornerRadius(10)

                        // Current Goals
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current Objectives")
                                .font(.headline)
                                .foregroundColor(themeManager.textColor)

                            if goalManager.goals.isEmpty {
                                Text("No objectives set. Add your first objective above.")
                                    .font(.caption)
                                    .foregroundColor(themeManager.textColor.opacity(0.6))
                                    .italic()
                            } else {
                                ForEach(goalManager.goals) { goal in
                                    SimpleGoalRow(goal: goal)
                                }
                            }
                        }
                        .padding()
                        .background(themeManager.secondaryBackgroundColor)
                        .cornerRadius(10)

                        // Quick Actions
                        VStack(spacing: 12) {
                            Button(action: {
                                goalManager.resetGoals()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("reset all completions")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(themeManager.accentColor)
                                .cornerRadius(10)
                            }
                            .disabled(goalManager.goals.isEmpty)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Meeting Goals")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("done") {
                        isPresented = false
                    }
                    .foregroundColor(themeManager.accentColor)
                }
            }
        }
    }

    private func addGoal() {
        guard !newGoalText.isEmpty else { return }
        goalManager.addGoal(newGoalText)
        newGoalText = ""
    }
}

// MARK: - Simple Goal Row
struct SimpleGoalRow: View {
    let goal: Goal
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack {
            if isEditing {
                TextField("Goal", text: $editText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        saveEdit()
                    }

                Button(action: saveEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else {
                Text(goal.text)
                    .font(.body)
                    .foregroundColor(themeManager.textColor)
                    .onTapGesture {
                        editText = goal.text
                        isEditing = true
                    }

                Spacer()

                Button(action: {
                    goalManager.deleteGoal(goal)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func saveEdit() {
        var updatedGoal = goal
        updatedGoal.text = editText
        goalManager.updateGoal(updatedGoal)
        isEditing = false
    }
}

struct GoalsManagementView_Previews: PreviewProvider {
    static var previews: some View {
        GoalsManagementView(isPresented: .constant(true))
            .environmentObject(GoalManager())
            .environmentObject(ThemeManager())
    }
}
