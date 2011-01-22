require 'fastercsv'
require 'tempfile'

class UserImportController < ApplicationController
  unloadable

  before_filter :require_admin

  USER_ATTRS = [:login, :password, :lastname, :firstname, :mail, :admin]

  def index
  end

  def match
    # params
    file = params[:file]
    splitter = params[:splitter]
    wrapper = params[:wrapper]
    encoding = params[:encoding]

    # save import file
    @original_filename = file.original_filename
    tmpfile = Tempfile.new("redmine_user_importer")
    if tmpfile
      tmpfile.write(file.read)
      tmpfile.close
      tmpfilename = File.basename(tmpfile.path)
      if !$tmpfiles
        $tmpfiles = Hash.new
      end
      $tmpfiles[tmpfilename] = tmpfile
    else
      flash[:error] = "Cannot save import file."
      return
    end

    session[:importer_tmpfile] = tmpfilename
    session[:importer_splitter] = splitter
    session[:importer_wrapper] = wrapper
    session[:importer_encoding] = encoding

    # display content
    @samples = []
    i = 0
    FasterCSV.foreach(tmpfile.path, {:headers=>true, :encoding=>encoding, :quote_char=>wrapper, :col_sep=>splitter}) do |row|
      @samples[i] = row
      i += 1
    end # do

    if @samples.size > 0
      @headers = @samples[0].headers
    end

    # fields
    @attrs = Array.new
    USER_ATTRS.each do |attr|
      @attrs.push([l_has_string?("field_#{attr}".to_sym) ? l("field_#{attr}".to_sym) : attr.to_s.humanize, attr])
    end
    @attrs.sort!
  end

  def result
    tmpfilename = session[:importer_tmpfile]
    splitter = session[:importer_splitter]
    wrapper = session[:importer_wrapper]
    encoding = session[:importer_encoding]

    if tmpfilename
      tmpfile = $tmpfiles[tmpfilename]
      if tmpfile == nil
        flash[:error] = l(:message_missing_imported_file)
        return
      end
    end

    # CSV fields map
    fields_map = params[:fields_map]
    # DB attr map
    attrs_map = fields_map.invert

    @handle_count = 0
    @failed_count = 0
    @failed_rows = Hash.new

    FasterCSV.foreach(tmpfile.path, {:headers=>true, :encoding=>encoding, :quote_char=>wrapper, :col_sep=>splitter}) do |row|
      user = User.find_by_login(row[attrs_map["login"]])
      unless user
        user = User.new(:status => 1, :mail_notification => 0, :language => Setting.default_language)
        user.login = row[attrs_map["login"]]
        user.password = row[attrs_map["password"]]
        user.password_confirmation = row[attrs_map["password"]]
        user.lastname = row[attrs_map["lastname"]]
        user.firstname = row[attrs_map["firstname"]]
        user.mail = row[attrs_map["mail"]]
        user.admin = row[attrs_map["admin"]]
      else
        flash[:warning] = l(:message_unique_filed_duplicated)
        @failed_count += 1
        @failed_rows[@handle_count + 1] = row
      end

      if (!user.save_without_validation!)
        @failed_count += 1
        @failed_rows[@handle_count + 1] = row
      end

      @handle_count += 1
    end # do

    if @failed_rows.size > 0
      @failed_rows = @failed_rows.sort
      @headers = @failed_rows[0][1].headers
    end
  end

end
