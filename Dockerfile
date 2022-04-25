FROM ruby:2.7.5

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

RUN apt-get -y update -qq

# install postgresql-client for easy importing of production database & vim
# for easy editing of credentials
RUN apt-get -y install postgresql-client vim poppler-utils
ENV EDITOR=vim

# Install yarn through npm to avoid this bug: https://github.com/docker/for-mac/issues/5864#issuecomment-884336317
RUN apt-get -y install nodejs npm
RUN npm install -g yarn

RUN gem install bundler -v 1.17.3

ADD yarn.lock /usr/src/app/yarn.lock
ADD package.json /usr/src/app/package.json
ADD Gemfile /usr/src/app/Gemfile
ADD Gemfile.lock /usr/src/app/Gemfile.lock

ENV BUNDLE_GEMFILE=Gemfile \
  BUNDLE_JOBS=4 \
  BUNDLE_PATH=/bundle

RUN bundle install
RUN yarn install --check-files

# Rubocop can't find config when ran with solargraph inside docker
# https://github.com/castwide/solargraph/issues/309#issuecomment-998137438
RUN ln -s /usr/src/app/.rubocop.yml ~/.rubocop.yml
RUN ln -s /usr/src/app/.rubocop_todo.yml ~/.rubocop_todo.yml

ADD . /usr/src/app
