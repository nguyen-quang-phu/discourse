# frozen_string_literal: true

require 'csv'

RSpec.describe Admin::WatchedWordsController do
  fab!(:admin) { Fabricate(:admin) }
  fab!(:user) { Fabricate(:user) }

  describe '#destroy' do
    fab!(:watched_word) { Fabricate(:watched_word) }

    context "when logged in as a non-staff user" do
      before do
        sign_in(user)
      end

      it "can't delete a watched word" do
        delete "/admin/customize/watched_words/#{watched_word.id}.json"

        expect(response.status).to eq(404)
      end
    end

    context "when logged in as staff user" do
      before do
        sign_in(admin)
      end

      it 'should return the right response when given an invalid id param' do
        delete "/admin/customize/watched_words/9999.json"

        expect(response.status).to eq(400)
      end

      it "should be able to delete a watched word" do
        delete "/admin/customize/watched_words/#{watched_word.id}.json"

        expect(response.status).to eq(200)
        expect(WatchedWord.find_by(id: watched_word.id)).to eq(nil)
        expect(UserHistory.where(action: UserHistory.actions[:watched_word_destroy]).count).to eq(1)
      end
    end
  end

  describe '#create' do
    context "when logged in as a non-staff user" do
      before do
        sign_in(user)
      end

      it "can't create a watched word" do
        post "/admin/customize/watched_words.json", params: {
          action_key: 'flag',
          word: 'Fr33'
        }

        expect(response.status).to eq(404)
      end
    end

    context "when logged in as a staff user" do
      before do
        sign_in(admin)
      end

      it 'creates a word with default case sensitivity' do
        post '/admin/customize/watched_words.json', params: {
          action_key: 'flag',
          word: 'Deals'
        }

        expect(response.status).to eq(200)
        expect(WatchedWord.take.word).to eq('Deals')
      end

      it 'creates a word with the given case sensitivity' do
        post '/admin/customize/watched_words.json', params: {
          action_key: 'flag',
          word: 'PNG',
          case_sensitive: true
        }

        expect(response.status).to eq(200)
        expect(WatchedWord.take.case_sensitive?).to eq(true)
        expect(WatchedWord.take.word).to eq('PNG')
      end
    end
  end

  describe '#upload' do
    context "when logged in as a non-staff user" do
      before do
        sign_in(user)
      end

      it "can't create watched words via file upload" do
        post "/admin/customize/watched_words/upload.json", params: {
          action_key: 'flag',
          file: Rack::Test::UploadedFile.new(file_from_fixtures("words.csv", "csv"))
        }

        expect(response.status).to eq(404)
      end
    end

    context 'when logged in as admin' do
      before do
        sign_in(admin)
        Fabricate(:tag, name: 'tag1')
        Fabricate(:tag, name: 'tag2')
        Fabricate(:tag, name: 'tag3')
      end

      it 'creates the words from the file' do
        post '/admin/customize/watched_words/upload.json', params: {
          action_key: 'flag',
          file: Rack::Test::UploadedFile.new(file_from_fixtures("words.csv", "csv"))
        }

        expect(response.status).to eq(200)
        expect(WatchedWord.count).to eq(6)

        expect(WatchedWord.pluck(:word)).to contain_exactly(
          'thread', '线', 'धागा', '실', 'tråd', 'нить'
        )

        expect(WatchedWord.pluck(:action).uniq).to eq([WatchedWord.actions[:flag]])
        expect(UserHistory.where(action: UserHistory.actions[:watched_word_create]).count).to eq(6)
      end

      it 'creates the words from the file' do
        post '/admin/customize/watched_words/upload.json', params: {
          action_key: 'tag',
          file: Rack::Test::UploadedFile.new(file_from_fixtures("words_tag.csv", "csv"))
        }

        expect(response.status).to eq(200)
        expect(WatchedWord.count).to eq(2)

        expect(WatchedWord.pluck(:word, :replacement)).to contain_exactly(
          ['hello', 'tag1,tag2'],
          ['world', 'tag2,tag3']
        )

        expect(WatchedWord.pluck(:action).uniq).to eq([WatchedWord.actions[:tag]])
        expect(UserHistory.where(action: UserHistory.actions[:watched_word_create]).count).to eq(2)
      end

      it 'creates case-sensitive words from the file' do
        post '/admin/customize/watched_words/upload.json', params: {
          action_key: 'flag',
          file: Rack::Test::UploadedFile.new(file_from_fixtures("words_case_sensitive.csv", "csv"))
        }

        expect(response.status).to eq(200)
        expect(WatchedWord.pluck(:word, :case_sensitive)).to contain_exactly(
          ['hello', true],
          ['UN', true],
          ['world', false],
          ['test', false]
        )
      end
    end
  end

  describe '#download' do
    context 'when not logged in as admin' do
      it "doesn't allow performing #download" do
        get "/admin/customize/watched_words/action/block/download"
        expect(response.status).to eq(404)
      end
    end

    context 'when logged in as admin' do
      before do
        sign_in(admin)
        Fabricate(:tag, name: 'tag1')
        Fabricate(:tag, name: 'tag2')
        Fabricate(:tag, name: 'tag3')
      end

      it "words of different actions are downloaded separately" do
        block_word_1 = Fabricate(:watched_word, action: WatchedWord.actions[:block])
        block_word_2 = Fabricate(:watched_word, action: WatchedWord.actions[:block])
        censor_word_1 = Fabricate(:watched_word, action: WatchedWord.actions[:censor])
        autotag_1 = Fabricate(:watched_word, action: WatchedWord.actions[:tag], replacement: "tag1,tag2")
        autotag_2 = Fabricate(:watched_word, action: WatchedWord.actions[:tag], replacement: "tag3,tag2")

        get "/admin/customize/watched_words/action/block/download"
        expect(response.status).to eq(200)
        block_words = response.body.split("\n")
        expect(block_words).to contain_exactly(block_word_1.word, block_word_2.word)

        get "/admin/customize/watched_words/action/censor/download"
        expect(response.status).to eq(200)
        censor_words = response.body.split("\n")
        expect(censor_words).to contain_exactly(censor_word_1.word)

        get "/admin/customize/watched_words/action/tag/download"
        expect(response.status).to eq(200)
        tag_words = response.body.split("\n").map(&:parse_csv)
        expect(tag_words).to contain_exactly(
          [autotag_1.word, autotag_1.replacement],
          [autotag_2.word, autotag_2.replacement]
        )
      end
    end
  end

  describe '#clear_all' do
    context 'with non admins' do
      it "doesn't allow them to perform #clear_all" do
        word = Fabricate(:watched_word, action: WatchedWord.actions[:block])
        delete "/admin/customize/watched_words/action/block"
        expect(response.status).to eq(404)
        expect(WatchedWord.pluck(:word)).to include(word.word)
      end
    end

    context 'with admins' do
      before do
        sign_in(admin)
      end

      it "allows them to perform #clear_all" do
        word = Fabricate(:watched_word, action: WatchedWord.actions[:block])
        delete "/admin/customize/watched_words/action/block.json"
        expect(response.status).to eq(200)
        expect(WatchedWord.pluck(:word)).not_to include(word.word)
        expect(UserHistory.where(action: UserHistory.actions[:watched_word_destroy]).count).to eq(1)
      end

      it "doesn't delete words of multiple actions in one call" do
        block_word = Fabricate(:watched_word, action: WatchedWord.actions[:block])
        flag_word = Fabricate(:watched_word, action: WatchedWord.actions[:flag])

        delete "/admin/customize/watched_words/action/flag.json"
        expect(response.status).to eq(200)
        all_words = WatchedWord.pluck(:word)
        expect(all_words).to include(block_word.word)
        expect(all_words).not_to include(flag_word.word)
        expect(UserHistory.where(action: UserHistory.actions[:watched_word_destroy]).count).to eq(1)
      end
    end
  end
end
