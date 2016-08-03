# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
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

require 'avalon/stream_mapper'

class Derivative < ActiveFedora::Base
  include ActiveFedora::Associations

  # belongs_to :masterfile, class_name:'MasterFile', predicate: ActiveFedora::RDF::Fcrepo::RelsExt.isDerivationOf

  # These fields do not fit neatly into the Dublin Core so until a long
  # term solution is found they are stored in a simple datastream in a
  # relatively flat structure.
  #
  # The only meaningful value at the moment is the url, which points to
  # the stream location. The other two are just stored until a migration
  # strategy is required.
  property :location_url, predicate: Avalon::RDFVocab::Derivative.locationURL, multiple: false
  property :hls_url, predicate: Avalon::RDFVocab::Derivative.hlsURL, multiple: false
  property :duration, predicate: Avalon::RDFVocab::Derivative.duration, multiple: false
  property :track_id, predicate: Avalon::RDFVocab::Derivative.trackID, multiple: false
  property :hls_track_id, predicate: Avalon::RDFVocab::Derivative.hlsTrackID, multiple: false
  property :managed, predicate: Avalon::RDFVocab::Derivative.isManaged, multiple: false
  property :derivativeFile, predicate: Avalon::RDFVocab::Derivative.derivativeFile, multiple: false

  has_subresource 'encoding', class_name: 'EncodingProfileDocument'

  before_destroy :retract_distributed_files!

  def initialize(*args)
    super(*args)
    self.managed = true
  end

  def self.from_output(dists, managed=true)
    #output is an array of 1 or more distributions of the same derivative (e.g. file and HLS segmented file)
    hls_output = dists.delete(dists.find {|o| o[:url].ends_with? "m3u8" or ( o[:hls_url].present? and o[:hls_url].ends_with? "m3u8" ) })
    output = dists.first || hls_output

    derivative = Derivative.new
    derivative.managed = managed
    derivative.track_id = output[:id]
    derivative.duration = output[:duration]
    derivative.encoding.mime_type = output[:mime_type]
    derivative.encoding.quality = output[:label].sub(/quality-/, '')

    derivative.encoding.audio.audio_bitrate = output[:audio_bitrate]
    derivative.encoding.audio.audio_codec = output[:audio_codec]
    derivative.encoding.video.video_bitrate = output[:video_bitrate]
    derivative.encoding.video.video_codec = output[:video_codec]
    derivative.encoding.video.resolution = "#{output[:width]}x#{output[:height]}" if output[:width] && output[:height]

    if hls_output
      derivative.hls_track_id = hls_output[:id]
      derivative.hls_url = hls_output[:hls_url].present? ? hls_output[:hls_url] : hls_output[:url]
    end
    derivative.location_url = output[:url]
    derivative.absolute_location = output[:url]

    derivative
  end

  def set_streaming_locations!
    if !!self.managed
      path = URI.parse(absolute_location).path
      self.location_url = Avalon::StreamMapper.map(path,'rtmp',self.format)
      self.hls_url      = Avalon::StreamMapper.map(path,'http',self.format)
    end
    self
  end

  def absolute_location
    derivativeFile
  end

  def absolute_location=(value)
    derivativeFile = value
    set_streaming_locations!
    derivativeFile
  end

  def tokenized_url(token, mobile=false)
    #uri = URI.parse(url.first)
    uri = streaming_url(mobile)
    "#{uri.to_s}?token=#{token}".html_safe
  end

  def streaming_url(is_mobile=false)
    is_mobile ? self.hls_url : self.location_url
  end

  def format
    case
      when (not encoding.video.empty?)
        "video"
      when (not encoding.audio.empty?)
        "audio"
      else
        "other"
    end
  end

  def to_solr(solr_doc = {})
    super(solr_doc)
    solr_doc['stream_path_ssi'] = location_url.split(/:/).last if location_url.present?
    solr_doc
  end

  private

    def retract_distributed_files!
      encode = masterfile.encoder_class.find(masterfile.workflow_id)
      encode.remove_output!(track_id) if track_id.present?
      encode.remove_output!(hls_track_id) if hls_track_id.present? && track_id != hls_track_id
    rescue StandardError => e
      logger.warn "Error deleting derivative: #{e.message}"
    end
end