# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

require_relative "../../common"
require_relative "../pages/speedgrader_page"

describe "speed grader - discussion submissions" do
  include_context "in-process server selenium tests"

  before do
    course_with_teacher_logged_in
    outcome_with_rubric
    @assignment = @course.assignments.create(
      name: "some topic",
      points_possible: 10,
      submission_types: "discussion_topic",
      description: "a little bit of content"
    )
    student = user_with_pseudonym(
      name: "first student",
      active_user: true,
      username: "student@example.com",
      password: "qwertyuiop"
    )
    @course.enroll_user(student, "StudentEnrollment", enrollment_state: "active")
    # create and enroll second student
    student_2 = user_with_pseudonym(
      name: "second student",
      active_user: true,
      username: "student2@example.com",
      password: "qwertyuiop"
    )
    @course.enroll_user(student_2, "StudentEnrollment", enrollment_state: "active")

    # create discussion entries
    @first_message = "uno student message"
    @second_message = "dos student message"
    @discussion_topic = DiscussionTopic.find_by(assignment_id: @assignment.id)
    @entry = @discussion_topic.discussion_entries
                              .create!(user: student, message: @first_message)
    @entry.update_topic
    @entry.context_module_action
    @attachment_thing = attachment_model(context: student_2, filename: "horse.doc", content_type: "application/msword")
    @entry_2 = @discussion_topic.discussion_entries
                                .create!(user: student_2, message: @second_message, attachment: @attachment_thing)
    @entry_2.update_topic
    @entry_2.context_module_action
    @student = student
    @student_2 = student_2
  end

  context "when react_discussions_post feature flag is OFF" do
    before :once do
      Account.default.disable_feature!(:react_discussions_post)
    end

    it "displays discussion entries for only one student", priority: "1" do
      Speedgrader.visit(@course.id, @assignment.id)

      # check for correct submissions in speed grader iframe
      in_frame "speedgrader_iframe", "#discussion_view_link" do
        expect(f("#main")).to include_text(@first_message)
        expect(f("#main")).not_to include_text(@second_message)
      end
      f("#next-student-button").click
      wait_for_ajax_requests
      in_frame "speedgrader_iframe", "#discussion_view_link" do
        expect(f("#main")).not_to include_text(@first_message)
        expect(f("#main")).to include_text(@second_message)
        url = f("#main div.attachment_data a")["href"]
        expect(url).to include "/files/#{@attachment_thing.id}/download?verifier=#{@attachment_thing.uuid}"
        expect(url).not_to include "/courses/#{@course}"
      end
    end

    context "when student names hidden" do
      it "hides the name of student on discussion iframe", priority: "2" do
        Speedgrader.visit(@course.id, @assignment.id)

        Speedgrader.click_settings_link
        Speedgrader.click_options_link
        Speedgrader.select_hide_student_names
        expect_new_page_load { fj(".ui-dialog-buttonset .ui-button:visible:last").click }

        # check for correct submissions in speed grader iframe
        in_frame "speedgrader_iframe", "#discussion_view_link" do
          expect(f("#main")).to include_text("This Student")
        end
      end

      it "hides student names and shows name of grading teacher" \
         "entries on both discussion links",
         priority: "2" do
        teacher = @course.teachers.first
        teacher_message = "why did the taco cross the road?"

        teacher_entry = @discussion_topic.discussion_entries
                                         .create!(user: teacher, message: teacher_message)
        teacher_entry.update_topic
        teacher_entry.context_module_action

        Speedgrader.visit(@course.id, @assignment.id)

        Speedgrader.click_settings_link
        Speedgrader.click_options_link
        Speedgrader.select_hide_student_names
        expect_new_page_load { fj(".ui-dialog-buttonset .ui-button:visible:last").click }

        # check for correct submissions in speed grader iframe
        in_frame "speedgrader_iframe", "#discussion_view_link" do
          f("#discussion_view_link").click
          wait_for_ajaximations
          authors = ff("h2.discussion-title span")
          expect(authors).to have_size(3)
          author_text = authors.map(&:text).join("\n")
          expect(author_text).to include("This Student")
          expect(author_text).to include("Discussion Participant")
          expect(author_text).to include(teacher.name)
        end
      end

      it "hides avatars on entries on both discussion links", priority: "2" do
        Speedgrader.visit(@course.id, @assignment.id)

        Speedgrader.click_settings_link
        Speedgrader.click_options_link
        Speedgrader.select_hide_student_names
        expect_new_page_load { fj(".ui-dialog-buttonset .ui-button:visible:last").click }

        # check for correct submissions in speed grader iframe
        in_frame "speedgrader_iframe", "#discussion_view_link" do
          f("#discussion_view_link").click
          expect(f("body")).not_to contain_css(".avatar")
        end

        Speedgrader.visit(@course.id, @assignment.id)

        in_frame "speedgrader_iframe", "#discussion_view_link" do
          f(".header_title a").click
          expect(f("body")).not_to contain_css(".avatar")
        end
      end
    end
  end

  context "when react_discussions_post feature flag is ON" do
    before :once do
      Account.default.enable_feature!(:react_discussions_post)
    end

    it "displays the discussion view with the first student entry highlighted" do
      Speedgrader.visit(@course.id, @assignment.id)
      in_frame "speedgrader_iframe", "#application" do
        x = f("#discussion_preview_iframe")
        expect(x.attribute("src")).to include("/courses/#{@course.id}/discussion_topics/#{@discussion_topic.id}?embed=true&entry_id=#{@entry.id}")
        in_frame "discussion_preview_iframe" do
          wait_for(method: nil, timeout: 5) { f("div[data-testid='isHighlighted']") }
          expect(f("div[data-testid='isHighlighted']")).to include_text(@first_message)
        end
      end
    end

    it "also displays the discussion view with the second student entry highlighted for graded group discussions" do
      group_discussion_assignment
      @group1.add_user @student
      child_topic = @topic.child_topic_for(@student)
      entry = child_topic.discussion_entries.create!(user: @student, message: @first_message)
      entry.update_topic

      Speedgrader.visit(@course.id, @assignment.id)
      in_frame "speedgrader_iframe", "#application" do
        x = f("#discussion_preview_iframe")
        expect(x.attribute("src")).to include("/groups/#{@group1.id}/discussion_topics/#{child_topic.id}?embed=true&entry_id=#{entry.id}")
        in_frame "discussion_preview_iframe" do
          wait_for(method: nil, timeout: 5) { f("div[data-testid='isHighlighted']") }
          expect(f("div[data-testid='isHighlighted']")).to include_text(@first_message)
        end
      end
    end

    it "hides student names (not teachers though) when hide student names is ON" do
      teacher_message = "why did the taco cross the road?"
      teacher_entry = @discussion_topic.discussion_entries
                                       .create!(user: @teacher, message: teacher_message)
      teacher_entry.update_topic

      Speedgrader.visit(@course.id, @assignment.id)

      Speedgrader.click_settings_link
      Speedgrader.click_options_link
      Speedgrader.select_hide_student_names
      force_click_native(".submit_button")
      wait_for_ajaximations

      # this includes turning the name into this student or discussion participant
      # also includes using anonymous avatars
      in_frame "speedgrader_iframe", "#application" do
        x = f("#discussion_preview_iframe")
        expect(x.attribute("src")).to include("/courses/#{@course.id}/discussion_topics/#{@discussion_topic.id}?embed=true&entry_id=#{@entry.id}&hidden_user_id=#{@student.id}")
        in_frame "discussion_preview_iframe" do
          wait_for(method: nil, timeout: 5) { f("div[data-testid='isHighlighted']") }

          highlighted_entry = f("div[data-testid='isHighlighted']")
          expect(highlighted_entry).to include_text(@first_message)
          expect(highlighted_entry).to include_text("This Student")
          expect(highlighted_entry).to include_text("Manage Discussion by This Student")
          expect(highlighted_entry).not_to include_text(@student.name)
          expect(highlighted_entry).not_to include_text("Manage Discussion by #{@student.name}")

          other_student_entry = fj("div[data-testid='notHighlighted']:contains('#{@second_message}')")
          expect(other_student_entry).to include_text("Discussion Participant")
          expect(other_student_entry).to include_text("Manage Discussion by Discussion Participant")
          expect(other_student_entry).not_to include_text(@student_2.name)
          expect(other_student_entry).not_to include_text("Manage Discussion by #{@student_2.name}")

          teacher_ui_entry = fj("div[data-testid='notHighlighted']:contains('#{teacher_message}')")
          expect(teacher_ui_entry).to include_text(@teacher.name)
          expect(teacher_ui_entry).to include_text("Manage Discussion by #{@teacher.name}")
          expect(teacher_ui_entry).not_to include_text("Discussion Participant")
          expect(teacher_ui_entry).not_to include_text("Manage Discussion by Discussion Participant")
        end
      end
    end
  end
end
