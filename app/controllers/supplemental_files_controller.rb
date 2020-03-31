# Copyright 2011-2020, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

class SupplementalFilesController < ApplicationController
  before_action :set_master_file
  before_action :build_supplemental_file, only: [:create, :update]

  rescue_from Avalon::SaveError do |exception|
    message = "An error occurred when saving the supplemental file: #{exception.full_message}"
    handle_error(message: message, status: 500)
  end

  rescue_from Avalon::BadRequest do |exception|
    handle_error(message: exception.full_message, status: 400)
  end

  rescue_from Avalon::NotFound do |exception|
    handle_error(message: exception.full_message, status: 404)
  end

  def create
    authorize! :edit, @master_file
    # FIXME: move filedata to permanent location
    raise Avalon::BadRequest, "Missing required parameters" unless supplemental_file_params[:file]

    absolute_path = supplemental_file_params[:file].path
    @supplemental_file.absolute_path = absolute_path
    @supplemental_file.label ||= supplemental_file_params[:file].original_filename
    @supplemental_file.id = @master_file.next_supplemental_file_id
    @master_file.supplemental_files += [@supplemental_file]
    raise Avalon::SaveError, @master_file.errors[:supplemental_files_json].full_messages unless @master_file.save

    flash[:success] = "Supplemental file successfully added."
    respond_to do |format|
      format.html { redirect_to edit_media_object_path(@master_file.media_object_id, step: 'structure') }
      format.json { head :created, location: master_file_supplemental_file_path(id: @supplemental_file.id, master_file_id: @master_file.id) }
    end
  end

  def show
    # TODO: Use a master file presenter which reads from solr instead of loading the masterfile from fedora
    authorize! :read, @master_file, message: "You do not have sufficient privileges"
    matching_file = @master_file.supplemental_files.find { |file| file.id == params[:id] }
    # FIXME: redirect or proxy the content instead of rails directly sending the file
    send_file matching_file.absolute_path
  end

  # Update the label of the supplemental file
  def update
    authorize! :edit, @master_file
    file_index = @master_file.supplemental_files.find_index { |file| file.id == @supplemental_file.id }
    raise Avalon::NotFound, "Cannot update the supplemental file: #{@supplemental_file.id} not found" unless file_index.present?
    raise Avalon::BadRequest, "Updating file contents not allowed" if supplemental_file_params[:file].present?

    # Use the stored absolute path and not update from the user params
    @supplemental_file.absolute_path = @master_file.supplemental_files[file_index].absolute_path
    supplemental_files = @master_file.supplemental_files
    supplemental_files[file_index] = @supplemental_file
    @master_file.supplemental_files = supplemental_files
    raise Avalon::SaveError, @master_file.errors[:supplemental_files_json].full_messages unless @master_file.save

    flash[:success] = "Supplemental file successfully updated."
    respond_to do |format|
      format.html { redirect_to edit_media_object_path(@master_file.media_object_id, step: 'structure') }
      format.json { head :ok, location: master_file_supplemental_file_path(id: @supplemental_file.id, master_file_id: @master_file.id) }
    end
  end

  def destroy
    authorize! :edit, @master_file
    file = @master_file.supplemental_files.find { |f| f.id == params[:id] }
    raise Avalon::NotFound, "Cannot update the supplemental file: #{params[:id]} not found" unless file.present?
    @master_file.supplemental_files -= [file]

    raise Avalon::SaveError, "An error occurred when deleting the supplemental file: #{@master_file.errors[:supplemental_files_json].full_messages}" unless @master_file.save

    flash[:success] = "Supplemental file successfully deleted."
    respond_to do |format|
      format.html { redirect_to edit_media_object_path(@master_file.media_object_id, step: 'structure') }
      format.json { head :no_content }
    end
  end

  private

    def set_master_file
      @master_file = MasterFile.find(params[:master_file_id])
    end

    def build_supplemental_file
      # Note that built supplemental file does not have an absolute_path
      @supplemental_file = MasterFile::SupplementalFile.new(id: params[:id], label: supplemental_file_params[:label])
    end

    def supplemental_file_params
      # TODO: Add parameters for minio and s3
      params.fetch(:supplemental_file, {}).permit(:label, :file)
    end

    def handle_error(message:, status:)
      if request.format == :json
        render json: { errors: message }, status: status
      else
        flash[:error] = message
        redirect_to edit_media_object_path(@master_file.media_object_id, step: 'structure')
      end
    end
end
